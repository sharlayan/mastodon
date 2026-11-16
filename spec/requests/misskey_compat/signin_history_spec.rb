# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat sign-in history endpoint' do
  let(:user)  { Fabricate(:user) }
  let(:token) { MisskeyCompat::MiAuth.issue_native_token(user).token }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  it 'lists the caller Mastodon login activities newest first with Misskey pagination and requires the native token' do
    older = user.login_activities.create!(authentication_method: :password, success: true, ip: '192.0.2.1', user_agent: 'Old UA', created_at: 2.days.ago)
    newer = user.login_activities.create!(authentication_method: :otp, success: false, failure_reason: 'invalid_otp', ip: '192.0.2.2', user_agent: 'New UA')
    Fabricate(:user).login_activities.create!(authentication_method: :password, success: true, ip: '192.0.2.3')

    post '/api/i/signin-history', params: { i: MisskeyCompat::MiAuth.issue_token(user, permission: 'read:account').token }, as: :json
    expect(response).to have_http_status(403)

    post '/api/i/signin-history', params: { i: token }, as: :json
    expect(response.parsed_body).to eq([
                                         { 'id' => MisskeyCompat::MiId.encode(newer.id), 'createdAt' => newer.created_at.iso8601, 'ip' => '192.0.2.2', 'headers' => { 'user-agent' => 'New UA' }, 'success' => false },
                                         { 'id' => MisskeyCompat::MiId.encode(older.id), 'createdAt' => older.created_at.iso8601, 'ip' => '192.0.2.1', 'headers' => { 'user-agent' => 'Old UA' }, 'success' => true },
                                       ])

    post '/api/i/signin-history', params: { i: token, untilId: MisskeyCompat::MiId.encode(newer.id) }, as: :json
    expect(response.parsed_body.pluck('id')).to eq([MisskeyCompat::MiId.encode(older.id)])

    post '/api/i/signin-history', params: { i: token, sinceId: MisskeyCompat::MiId.encode(older.id) }, as: :json
    expect(response.parsed_body.pluck('id')).to eq([MisskeyCompat::MiId.encode(newer.id)])
  end
end
