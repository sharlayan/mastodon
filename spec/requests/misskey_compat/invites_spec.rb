# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat invite codes' do
  let(:user)       { Fabricate(:user) }
  let(:account)    { user.account }
  let(:token)      { MisskeyCompat::MiAuth.issue_native_token(user).token }
  let(:read_token) { MisskeyCompat::MiAuth.issue_token(user, permission: 'read:invite-codes').token }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  it 'creates single-use Mastodon invites, lists them as InviteCode entities with usage, and reports no limit' do
    post '/api/invite/create', params: { i: token }, as: :json

    expect(response).to have_http_status(200)
    invite = Invite.find(MisskeyCompat::MiId.decode(response.parsed_body[:id]))
    expect(invite).to have_attributes(user: user, max_uses: 1, expires_at: nil)
    expect(response.parsed_body).to include(code: invite.code, expiresAt: nil, used: false, usedBy: nil, usedAt: nil)
    expect(response.parsed_body[:createdBy]).to include(id: MisskeyCompat::MiId.encode(account.id))

    invitee = Fabricate(:user, invite: invite, account: Fabricate(:account, username: 'invitee'))
    invite.update!(uses: 1)
    Fabricate(:invite, user: Fabricate(:user))

    post '/api/invite/list', params: { i: read_token }, as: :json

    expect(response.parsed_body.size).to eq(1)
    expect(response.parsed_body.first).to include(code: invite.code, used: true, usedAt: invitee.created_at.iso8601(3))
    expect(response.parsed_body.first[:usedBy]).to include(username: 'invitee')

    post '/api/invite/limit', params: { i: read_token }, as: :json
    expect(response.parsed_body).to eq({ 'remaining' => nil })

    post '/api/invite/create', params: { i: read_token }, as: :json
    expect(response).to have_http_status(403)
  end

  it 'expires the caller unused invites, protects used and foreign ones unless the caller manages invites' do
    unused = Fabricate(:invite, user: user)
    used = Fabricate(:invite, user: user, uses: 1)
    foreign = Fabricate(:invite, user: Fabricate(:user))

    post '/api/invite/delete', params: { i: token, inviteId: MisskeyCompat::MiId.encode(unused.id) }, as: :json
    expect(response).to have_http_status(204)
    expect(unused.reload.expired?).to be(true)

    post '/api/invite/delete', params: { i: token, inviteId: MisskeyCompat::MiId.encode(used.id) }, as: :json
    expect(response.parsed_body[:error]).to include(code: 'CAN_NOT_DELETE_INVITE_CODE', id: 'ff17af39-000c-4d4e-abdf-848fa30fc1ce')

    post '/api/invite/delete', params: { i: token, inviteId: MisskeyCompat::MiId.encode(foreign.id) }, as: :json
    expect(response.parsed_body[:error]).to include(code: 'ACCESS_DENIED', id: '5eb8d909-2540-4970-90b8-dd6f86088121')

    post '/api/invite/delete', params: { i: token, inviteId: MisskeyCompat::MiId.encode(foreign.id + 1000) }, as: :json
    expect(response).to have_http_status(404)
    expect(response.parsed_body[:error]).to include(code: 'NO_SUCH_INVITE_CODE', id: 'cd4f9ae4-7854-4e3e-8df9-c296f051e634')

    user.update!(role: Fabricate(:user_role, permissions: UserRole::FLAGS[:manage_invites]))

    [used, foreign].each do |invite|
      post '/api/invite/delete', params: { i: token, inviteId: MisskeyCompat::MiId.encode(invite.id) }, as: :json
      expect(response).to have_http_status(204)
      expect(invite.reload.expired?).to be(true)
    end
  end

  it 'refuses every invite endpoint when the caller role cannot invite' do
    UserRole.everyone.update!(permissions: 0)
    invite = Fabricate(:invite, user: user)

    %w(create list limit delete).each do |endpoint|
      post "/api/invite/#{endpoint}", params: { i: token, inviteId: MisskeyCompat::MiId.encode(invite.id) }, as: :json

      expect(response).to have_http_status(403), endpoint
      expect(response.parsed_body[:error]).to include(code: 'ROLE_PERMISSION_DENIED', kind: 'permission'), endpoint
    end
    expect(invite.reload.expired?).to be(false)
  end
end
