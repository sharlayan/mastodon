# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat admin moderation logs' do
  let(:role)         { Fabricate(:user_role, permissions: UserRole::FLAGS[:view_audit_log], position: 10) }
  let(:auditor)      { Fabricate(:user, role: role) }
  let(:token)        { MisskeyCompat::MiAuth.issue_native_token(auditor).token }
  let(:target)       { Fabricate(:account, username: 'spammer') }
  let(:moderator)    { Fabricate(:account, username: 'modguy') }
  let!(:suspend_log) { Admin::ActionLog.create!(account: moderator, action: :suspend, target: target) }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  it 'maps Mastodon action logs to Misskey moderation log types' do
    report = Fabricate(:report)
    MisskeyAbuseReportResolution.record!(report, 'reject')
    resolve_log = Admin::ActionLog.create!(account: moderator, action: :resolve, target: report)
    role_log = Admin::ActionLog.create!(account: moderator, action: :update, target: role)
    Admin::ActionLog.create!(account: moderator, action: :create, target: Fabricate(:custom_emoji))

    post '/api/admin/show-moderation-logs', params: { i: token }, as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body.pluck(:id)).to eq([role_log, resolve_log, suspend_log].map { |log| MisskeyCompat::MiId.encode(log.id) })
    expect(response.parsed_body.pluck(:type)).to eq(%w(updateRole resolveAbuseReport suspend))
    expect(response.parsed_body.last).to include(userId: MisskeyCompat::MiId.encode(moderator.id), user: a_hash_including(username: 'modguy'), info: { userId: MisskeyCompat::MiId.encode(target.id), userUsername: 'spammer', userHost: nil })
    expect(response.parsed_body.second[:info]).to include(reportId: MisskeyCompat::MiId.encode(report.id), resolvedAs: 'reject')
    expect(response.parsed_body.first.dig(:info, :before, :id)).to eq(MisskeyCompat::MiId.encode(role.id))
  end

  it 'filters by type, moderator and search text and requires the audit log permission' do
    Admin::ActionLog.create!(account: moderator, action: :unsuspend, target: Fabricate(:account, username: 'other'))

    post '/api/admin/show-moderation-logs', params: { i: token, type: 'suspend' }, as: :json
    expect(response.parsed_body.pluck(:type)).to eq(%w(suspend))

    post '/api/admin/show-moderation-logs', params: { i: token, search: 'spam', userId: MisskeyCompat::MiId.encode(moderator.id) }, as: :json
    expect(response.parsed_body.pluck(:type)).to eq(%w(suspend))

    post '/api/admin/show-moderation-logs', params: { i: token, type: 'clearQueue' }, as: :json
    expect(response.parsed_body).to eq([])

    post '/api/admin/show-moderation-logs', params: { i: MisskeyCompat::MiAuth.issue_native_token(Fabricate(:user, role: Fabricate(:user_role, permissions: UserRole::FLAGS[:manage_users]))).token }, as: :json
    expect(response.parsed_body.dig(:error, :code)).to eq('ACCESS_DENIED')
  end
end
