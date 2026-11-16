# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat admin system webhooks' do
  let(:role) { Fabricate(:user_role, permissions: UserRole::FLAGS[:manage_webhooks] | UserRole::FLAGS[:manage_reports] | UserRole::FLAGS[:manage_users]) }
  let(:user) { Fabricate(:user, role: role) }
  let(:token) { MisskeyCompat::MiAuth.issue_native_token(user).token }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  def api(path, **params)
    post "/api/admin/system-webhook/#{path}", params: { i: token }.merge(params), as: :json
    response.parsed_body
  end

  it 'manages Mastodon admin webhooks with Misskey event names and keeps Mastodon-only events' do
    created = api('create', isActive: true, name: 'Reports', on: %w(abuseReport userCreated), url: 'https://hooks.example/a', secret: 'abcdefghijklmnop')
    webhook = Webhook.find(MisskeyCompat::MiId.decode(created[:id]))

    expect(created).to include(name: 'Reports', on: %w(abuseReport userCreated), isActive: true, secret: 'abcdefghijklmnop', latestSentAt: nil)
    expect(webhook.events).to contain_exactly('report.created', 'account.created')

    webhook.update!(events: webhook.events + %w(account.approved))
    updated = api('update', id: created[:id], isActive: false, name: 'Renamed', on: %w(abuseReportResolved), url: 'https://hooks.example/b', secret: '')
    expect(updated).to include(name: 'Renamed', on: %w(abuseReportResolved), isActive: false, secret: 'abcdefghijklmnop')
    expect(webhook.reload.events).to contain_exactly('account.approved', 'report.updated')

    expect(api('list', isActive: false).pluck(:id)).to eq([created[:id]])
    expect(api('list', on: %w(userCreated))).to eq([])
    expect(api('show', id: created[:id])).to include(url: 'https://hooks.example/b')

    api('delete', id: created[:id])
    expect(Webhook.exists?(webhook.id)).to be(false)
    expect(MisskeySystemWebhook.count).to eq(0)
  end

  it 'rejects unmappable events and delivers Mastodon-format test payloads to the override URL' do
    api('create', isActive: true, name: 'Mods', on: %w(inactiveModeratorsWarning), url: 'https://hooks.example/a')
    expect(response.parsed_body.dig(:error, :info, :param)).to eq('#/properties/on')

    webhook = Fabricate(:webhook, events: %w(report.created), url: 'https://hooks.example/original')
    request = stub_request(:post, 'https://hooks.example/override').with { |req| JSON.parse(req.body)['event'] == 'report.created' && req.headers['X-Hub-Signature'].start_with?('sha256=') }

    api('test', webhookId: MisskeyCompat::MiId.encode(webhook.id), type: 'abuseReport', override: { url: 'https://hooks.example/override', secret: 'override-secret-123' })
    expect(response).to have_http_status(204)
    MisskeyCompatSystemWebhookTestWorker.drain
    expect(request).to have_been_requested

    api('show', id: 'missing0000000000')
    expect(response.parsed_body.dig(:error, :id)).to eq('38dd1ffe-04b4-6ff5-d8ba-4e6a6ae22c9d')
  end

  it 'requires a native token and the webhook permission' do
    post '/api/admin/system-webhook/list', params: { i: MisskeyCompat::MiAuth.issue_token(user, permission: 'read:account').token }, as: :json
    expect(response.parsed_body.dig(:error, :code)).to eq('ACCESS_DENIED')

    user.update!(role: Fabricate(:user_role, permissions: UserRole::FLAGS[:manage_reports]))
    api('list')
    expect(response.parsed_body.dig(:error, :code)).to eq('ROLE_PERMISSION_DENIED')
  end
end
