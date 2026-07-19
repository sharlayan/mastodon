# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat near-miss endpoints' do
  let(:user)        { Fabricate(:user) }
  let(:token)       { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write').token }
  let(:read_token)  { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read').token }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  describe 'POST /api/announcements/show' do
    let!(:announcement) do
      BoardAnnouncement.create!(title: 'Notice', text: 'Details', published: true, published_at: Time.now.utc)
    end

    it 'returns a visible published announcement' do
      post '/api/announcements/show', params: { i: read_token, announcementId: MisskeyCompat::MiId.encode(announcement.id) }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to include('id' => MisskeyCompat::MiId.encode(announcement.id), 'title' => 'Notice', 'text' => 'Details', 'isRead' => false)
    end

    it 'does not expose an unpublished announcement' do
      announcement.update!(published: false)

      post '/api/announcements/show', params: { i: read_token, announcementId: MisskeyCompat::MiId.encode(announcement.id) }, as: :json

      expect(response).to have_http_status(404)
      expect(response.parsed_body.dig('error', 'code')).to eq('NO_SUCH_ANNOUNCEMENT')
    end
  end

  describe 'POST /api/ap/get' do
    let(:role)       { Fabricate(:user_role, permissions: UserRole::FLAGS[:administrator], position: 100) }
    let(:admin)      { Fabricate(:user, role: role) }
    let(:admin_token) { Fabricate(:accessible_access_token, resource_owner_id: admin.id, scopes: 'read').token }
    let(:uri)        { 'https://remote.example/users/alice' }
    let(:object)     { { '@context' => 'https://www.w3.org/ns/activitystreams', 'id' => uri, 'type' => 'Person' } }

    it 'returns the raw ActivityPub object to an administrator' do
      dereferencer = instance_double(ActivityPub::Dereferencer, object: object)
      allow(ActivityPub::Dereferencer).to receive(:new).with(uri, signature_actor: admin.account).and_return(dereferencer)

      post '/api/ap/get', params: { i: admin_token, uri: uri }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to eq(object)
    end

    it 'rejects a non-administrator' do
      post '/api/ap/get', params: { i: read_token, uri: uri }, as: :json

      expect(response).to have_http_status(403)
      expect(response.parsed_body.dig('error', 'code')).to eq('PERMISSION_DENIED')
    end

    it 'rejects non-HTTP URI schemes' do
      post '/api/ap/get', params: { i: admin_token, uri: 'file:///etc/passwd' }, as: :json

      expect(response).to have_http_status(400)
      expect(response.parsed_body.dig('error', 'code')).to eq('INVALID_PARAM')
    end
  end

  describe 'POST /api/hashtags/list' do
    let!(:local_tag)  { Fabricate(:tag, name: 'localtag') }
    let!(:remote_tag) { Fabricate(:tag, name: 'remotetag') }

    before do
      local_tag.accounts << user.account
      remote_tag.accounts << Fabricate(:account, domain: 'remote.example')
      remote_tag.accounts << Fabricate(:account, domain: 'elsewhere.example')
    end

    it 'sorts and filters by attached remote users' do
      post '/api/hashtags/list', params: { i: read_token, sort: '+attachedRemoteUsers', attachedToRemoteUserOnly: true, limit: 10 }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body.first).to include(
        'tag' => 'remotetag',
        'mentionedUsersCount' => 0,
        'attachedUsersCount' => 2,
        'attachedLocalUsersCount' => 0,
        'attachedRemoteUsersCount' => 2
      )
      expect(response.parsed_body.pluck('tag')).to_not include('localtag')
    end

    it 'rejects an unknown sort mode' do
      post '/api/hashtags/list', params: { i: read_token, sort: '+unknown' }, as: :json

      expect(response).to have_http_status(400)
      expect(response.parsed_body.dig('error', 'code')).to eq('INVALID_PARAM')
    end
  end

  describe 'POST /api/users/lists/update-membership' do
    let(:list)    { Fabricate(:list, account: user.account) }
    let(:member)  { Fabricate(:account) }
    let(:membership) { list.list_accounts.create!(account: member) }

    before do
      Fabricate(:follow, account: user.account, target_account: member)
      membership
    end

    it 'stores withReplies and exposes it from get-memberships' do
      post '/api/users/lists/update-membership', params: { i: token, listId: MisskeyCompat::MiId.encode(list.id), userId: MisskeyCompat::MiId.encode(member.id), withReplies: true }, as: :json

      expect(response).to have_http_status(204)
      expect(membership.reload.with_replies).to be(true)

      post '/api/users/lists/get-memberships', params: { i: read_token, listId: MisskeyCompat::MiId.encode(list.id) }, as: :json
      expect(response).to have_http_status(200)
      expect(response.parsed_body.first).to include('userId' => MisskeyCompat::MiId.encode(member.id), 'withReplies' => true)
    end

    it 'requires a write-scoped token' do
      post '/api/users/lists/update-membership', params: { i: read_token, listId: MisskeyCompat::MiId.encode(list.id), userId: MisskeyCompat::MiId.encode(member.id), withReplies: true }, as: :json

      expect(response).to have_http_status(403)
      expect(membership.reload.with_replies).to be(false)
    end

    it 'allows replies by a member with withReplies enabled' do
      membership.update!(with_replies: true)
      replied_to = Fabricate(:status, account: Fabricate(:account))
      reply = Fabricate(:status, account: member, in_reply_to_id: replied_to.id)

      expect(FeedManager.instance.send(:filter_from_list?, reply, list)).to be(false)
    end
  end

  describe 'endpoint advertisement' do
    it 'advertises all four implemented endpoints' do
      post '/api/endpoints', as: :json

      expect(response.parsed_body).to include('announcements/show', 'ap/get', 'hashtags/list', 'users/lists/update-membership')
    end
  end
end
