# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat admin abuse reports' do
  let(:role)            { Fabricate(:user_role, permissions: UserRole::FLAGS[:manage_reports], position: 10) }
  let(:moderator)       { Fabricate(:user, role: role) }
  let(:token)           { MisskeyCompat::MiAuth.issue_native_token(moderator).token }
  let(:remote_target)   { Fabricate(:account, domain: 'remote.example', username: 'bad', inbox_url: 'https://remote.example/inbox', uri: 'https://remote.example/users/bad') }
  let!(:local_report)   { Fabricate(:report, target_account: Fabricate(:account), comment: 'Local spam') }
  let!(:remote_report)  { Fabricate(:report, target_account: remote_target, comment: 'Remote spam') }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  def mid(id)
    MisskeyCompat::MiId.encode(id)
  end

  it 'enforces credentials and admin token permissions' do
    post '/api/admin/abuse-user-reports', as: :json
    expect(response).to have_http_status(401)

    app_token = MisskeyCompat::MiAuth.issue_token(moderator, permission: 'read:account').token
    post '/api/admin/abuse-user-reports', params: { i: app_token }, as: :json
    expect(response).to have_http_status(403)
    expect(response.parsed_body.dig(:error, :code)).to eq('PERMISSION_DENIED')

    read_oauth = Fabricate(:accessible_access_token, resource_owner_id: moderator.id, scopes: 'read write').token
    post '/api/admin/abuse-user-reports', params: { i: read_oauth }, as: :json
    expect(response).to have_http_status(403)

    admin_oauth = Fabricate(:accessible_access_token, resource_owner_id: moderator.id, scopes: 'admin:read:reports').token
    post '/api/admin/abuse-user-reports', params: { i: admin_oauth }, as: :json
    expect(response).to have_http_status(200)

    post '/api/admin/resolve-abuse-user-report', params: { i: admin_oauth, reportId: mid(local_report.id) }, as: :json
    expect(response).to have_http_status(403)
  end

  it 'requires a moderator role and the matching Mastodon permission' do
    user_token = MisskeyCompat::MiAuth.issue_native_token(Fabricate(:user)).token
    post '/api/admin/abuse-user-reports', params: { i: user_token }, as: :json
    expect(response).to have_http_status(403)
    expect(response.parsed_body[:error]).to include(code: 'ROLE_PERMISSION_DENIED', id: 'd33d5333-db36-423d-a8f9-1a2b9549da41')

    other_moderator = Fabricate(:user, role: Fabricate(:user_role, permissions: UserRole::FLAGS[:manage_users], position: 5))
    post '/api/admin/abuse-user-reports', params: { i: MisskeyCompat::MiAuth.issue_native_token(other_moderator).token }, as: :json
    expect(response).to have_http_status(403)
    expect(response.parsed_body.dig(:error, :code)).to eq('ACCESS_DENIED')
  end

  it 'lists reports with Misskey fields and filters' do
    Fabricate(:report_note, report: local_report, account: moderator.account, content: 'old')
    Fabricate(:report_note, report: local_report, account: moderator.account, content: 'latest')
    remote_report.update!(forwarded: true)

    post '/api/admin/abuse-user-reports', params: { i: token }, as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body.pluck(:id)).to eq([mid(remote_report.id), mid(local_report.id)])
    expect(response.parsed_body.last).to include(
      comment: 'Local spam',
      resolved: false,
      reporterId: mid(local_report.account_id),
      targetUserId: mid(local_report.target_account_id),
      assigneeId: nil,
      assignee: nil,
      forwarded: false,
      resolvedAs: nil,
      moderationNote: 'latest'
    )
    expect(response.parsed_body.last[:targetUser]).to include(id: mid(local_report.target_account_id), followersCount: 0)
    expect(response.parsed_body.first[:forwarded]).to be(true)

    post '/api/admin/abuse-user-reports', params: { i: token, targetUserOrigin: 'remote' }, as: :json
    expect(response.parsed_body.pluck(:id)).to eq([mid(remote_report.id)])

    post '/api/admin/abuse-user-reports', params: { i: token, sinceId: mid(local_report.id) }, as: :json
    expect(response.parsed_body.pluck(:id)).to eq([mid(remote_report.id)])

    post '/api/admin/abuse-user-reports', params: { i: token, targetUserOrigin: 'elsewhere' }, as: :json
    expect(response).to have_http_status(400)
  end

  it 'resolves reports with action logs and keeps resolvedAs, then filters by state' do
    post '/api/admin/resolve-abuse-user-report', params: { i: token, reportId: mid(local_report.id), resolvedAs: 'accept' }, as: :json

    expect(response).to have_http_status(204)
    expect(local_report.reload).to have_attributes(action_taken?: true, action_taken_by_account_id: moderator.account_id)
    expect(Admin::ActionLog.where(account: moderator.account, action: 'resolve', target: local_report)).to exist

    post '/api/admin/abuse-user-reports', params: { i: token, state: 'resolved' }, as: :json
    expect(response.parsed_body.sole).to include(id: mid(local_report.id), resolved: true, resolvedAs: 'accept', assigneeId: mid(moderator.account_id))

    post '/api/admin/resolve-abuse-user-report', params: { i: token, reportId: mid(local_report.id), resolvedAs: 'maybe' }, as: :json
    expect(response).to have_http_status(400)

    post '/api/admin/resolve-abuse-user-report', params: { i: token, reportId: mid(local_report.id) }, as: :json
    expect(MisskeyAbuseReportResolution.where(report: local_report)).to be_empty

    post '/api/admin/resolve-abuse-user-report', params: { i: token, reportId: '999999' }, as: :json
    expect(response).to have_http_status(404)
    expect(response.parsed_body[:error]).to include(code: 'NO_SUCH_ABUSE_REPORT', id: 'ac3794dd-2ce4-d878-e546-73c60c06b398')
  end

  it 'records moderation notes as Mastodon report notes' do
    post '/api/admin/update-abuse-user-report', params: { i: token, reportId: mid(local_report.id), moderationNote: 'Checked' }, as: :json
    post '/api/admin/update-abuse-user-report', params: { i: token, reportId: mid(local_report.id), moderationNote: 'Checked' }, as: :json
    post '/api/admin/update-abuse-user-report', params: { i: token, reportId: mid(local_report.id), moderationNote: '' }, as: :json

    expect(response).to have_http_status(204)
    expect(local_report.notes.pluck(:content, :account_id)).to eq([['Checked', moderator.account_id]])
  end

  it 'forwards remote reports once through ActivityPub and refuses local targets' do
    post '/api/admin/forward-abuse-user-report', params: { i: token, reportId: mid(remote_report.id) }, as: :json

    expect(response).to have_http_status(204)
    expect(remote_report.reload.forwarded).to be(true)
    expect(ActivityPub::DeliveryWorker).to have_enqueued_sidekiq_job(match_json_values(type: 'Flag', content: 'Remote spam'), Account.representative.id, 'https://remote.example/inbox')
    expect(Admin::ActionLog.where(action: 'update', target: remote_report)).to exist

    post '/api/admin/forward-abuse-user-report', params: { i: token, reportId: mid(remote_report.id) }, as: :json
    expect(response).to have_http_status(500)
    expect(response.parsed_body.dig(:error, :info, :e, :message)).to eq('The report has already been forwarded')

    post '/api/admin/forward-abuse-user-report', params: { i: token, reportId: mid(local_report.id) }, as: :json
    expect(response.parsed_body.dig(:error, :code)).to eq('INTERNAL_ERROR')
  end
end
