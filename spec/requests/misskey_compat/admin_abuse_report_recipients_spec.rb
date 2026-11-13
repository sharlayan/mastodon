# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat abuse report notification recipients' do
  let(:role)      { Fabricate(:user_role, permissions: UserRole::FLAGS[:manage_reports] | UserRole::FLAGS[:manage_webhooks], position: 10) }
  let(:moderator) { Fabricate(:user, role: role, confirmed_at: Time.now.utc) }
  let(:token)     { MisskeyCompat::MiAuth.issue_native_token(moderator).token }
  let(:webhook)   { Fabricate(:webhook, events: %w(report.created)) }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  def call(action, **params)
    post "/api/admin/abuse-report/notification-recipient/#{action}", params: { i: token }.merge(params), as: :json
  end

  it 'manages email and webhook recipients' do
    call('create', isActive: true, name: 'Mail', method: 'email', userId: MisskeyCompat::MiId.encode(moderator.account_id))
    created = response.parsed_body
    expect(created).to include(isActive: true, name: 'Mail', method: 'email', userId: MisskeyCompat::MiId.encode(moderator.account_id), user: a_hash_including(username: moderator.account.username))
    expect(created).to_not have_key(:systemWebhookId)

    call('update', id: created[:id], isActive: false, name: 'Hook', method: 'webhook', systemWebhookId: MisskeyCompat::MiId.encode(webhook.id))
    expect(response.parsed_body).to include(isActive: false, method: 'webhook', systemWebhook: a_hash_including(url: webhook.url, on: %w(abuseReport), secret: webhook.secret))
    expect(response.parsed_body).to_not have_key(:userId)

    call('list', method: %w(webhook))
    expect(response.parsed_body.pluck(:id)).to eq([created[:id]])

    call('show', id: created[:id])
    expect(response.parsed_body[:name]).to eq('Hook')

    call('delete', id: created[:id])
    expect(response).to have_http_status(204)
    call('show', id: created[:id])
    expect(response.parsed_body[:error]).to include(code: 'NO_SUCH_RECIPIENT', id: '013de6a8-f757-04cb-4d73-cc2a7e3368e4')
  end

  it 'validates recipients and requires a web session token' do
    call('create', isActive: true, name: 'Mail', method: 'email')
    expect(response.parsed_body.dig(:error, :code)).to eq('CORRELATION_CHECK_EMAIL')

    unconfirmed = Fabricate(:user, confirmed_at: nil)
    call('create', isActive: true, name: 'Mail', method: 'email', userId: MisskeyCompat::MiId.encode(unconfirmed.account_id))
    expect(response.parsed_body.dig(:error, :code)).to eq('EMAIL_ADDRESS_NOT_SET')

    call('create', isActive: true, name: 'Hook', method: 'webhook')
    expect(response.parsed_body.dig(:error, :code)).to eq('CORRELATION_CHECK_WEBHOOK')

    oauth = Fabricate(:accessible_access_token, resource_owner_id: moderator.id, scopes: 'admin:read admin:write').token
    post '/api/admin/abuse-report/notification-recipient/list', params: { i: oauth }, as: :json
    expect(response.parsed_body.dig(:error, :code)).to eq('ACCESS_DENIED')
    expect(MisskeyAbuseReportRecipient.count).to eq(0)
  end

  it 'emails active recipients about new reports when their Mastodon report emails are off', :inline_jobs do
    moderator.settings['notification_emails.report'] = false
    moderator.save!
    MisskeyAbuseReportRecipient.create!(name: 'Mail', delivery_method: 'email', account: moderator.account)
    MisskeyAbuseReportRecipient.create!(name: 'Off', delivery_method: 'email', account: Fabricate(:user, role: role).account, active: false)

    emails = capture_emails { ReportService.new.call(Fabricate(:account), Fabricate(:account), comment: 'spam') }

    expect(emails.flat_map(&:to).tally).to include(moderator.email => 1)
  end
end
