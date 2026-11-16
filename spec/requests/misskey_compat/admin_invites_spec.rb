# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat admin invites' do
  let(:role)      { Fabricate(:user_role, permissions: UserRole::FLAGS[:manage_invites] | UserRole::FLAGS[:invite_users], position: 10) }
  let(:moderator) { Fabricate(:user, role: role) }
  let(:token)     { MisskeyCompat::MiAuth.issue_native_token(moderator).token }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  it 'creates single-use Mastodon invites and validates parameters' do
    post '/api/admin/invite/create', params: { i: token, count: 2, expiresAt: '2030-01-02T03:04:05Z' }, as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body.size).to eq(2)
    expect(response.parsed_body.first).to include(expiresAt: '2030-01-02T03:04:05Z', used: false, usedBy: nil, usedAt: nil, createdBy: a_hash_including(username: moderator.account.username))
    expect(Invite.where(user: moderator).pluck(:max_uses, :expires_at)).to all(eq([1, Time.utc(2030, 1, 2, 3, 4, 5)]))

    post '/api/admin/invite/create', params: { i: token, expiresAt: 'not a date' }, as: :json
    expect(response.parsed_body[:error]).to include(code: 'INVALID_DATE_TIME', id: 'f1380b15-3760-4c6c-a1db-5c3aaf1cbd49')

    post '/api/admin/invite/create', params: { i: token, count: 101 }, as: :json
    expect(response).to have_http_status(400)
  end

  it 'lists invites with usage, type filters and sort orders' do
    unused = Fabricate(:invite, user: moderator, max_uses: 1)
    used = Fabricate(:invite, user: moderator, max_uses: 1, uses: 1)
    expired = Fabricate(:invite, user: moderator, expires_at: 1.day.ago)
    invitee = Fabricate(:user, invite: used, account_attributes: { username: 'invitee' })

    post '/api/admin/invite/list', params: { i: token }, as: :json
    expect(response.parsed_body.pluck(:code)).to eq([expired.code, used.code, unused.code])
    expect(response.parsed_body.second).to include(used: true, usedAt: invitee.created_at.iso8601, usedBy: a_hash_including(username: 'invitee'))

    { 'unused' => [expired.code, unused.code], 'used' => [used.code], 'expired' => [expired.code] }.each do |type, codes|
      post '/api/admin/invite/list', params: { i: token, type: type }, as: :json
      expect(response.parsed_body.pluck(:code)).to eq(codes), type
    end

    post '/api/admin/invite/list', params: { i: token, sort: '+usedAt', limit: 1 }, as: :json
    expect(response.parsed_body.pluck(:code)).to eq([used.code])

    post '/api/admin/invite/list', params: { i: MisskeyCompat::MiAuth.issue_native_token(Fabricate(:user, role: Fabricate(:user_role, permissions: UserRole::FLAGS[:manage_users]))).token }, as: :json
    expect(response.parsed_body.dig(:error, :code)).to eq('ACCESS_DENIED')
  end
end
