# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat federation' do
  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  describe 'federation/instances' do
    it 'lists instance snapshots and honours filters and sort' do
      Fabricate(:misskey_federation_instance_stat, domain: 'small.example', users_count: 1, following_count: 0, followers_count: 0)
      Fabricate(:misskey_federation_instance_stat, domain: 'big.example', users_count: 10, following_count: 5, followers_count: 5)

      post '/api/federation/instances', params: { sort: '+users', federating: true }, as: :json

      expect(response).to have_http_status(200)
      body = response.parsed_body
      expect(body.pluck(:host)).to eq(['big.example'])
      expect(body.first).to include(host: 'big.example', usersCount: 10)
    end
  end

  describe 'federation/show-instance' do
    it 'returns a single instance or null' do
      Fabricate(:misskey_federation_instance_stat, domain: 'known.example', users_count: 3)

      post '/api/federation/show-instance', params: { host: 'known.example' }, as: :json
      expect(response.parsed_body).to include(host: 'known.example', usersCount: 3)

      post '/api/federation/show-instance', params: { host: 'unknown.example' }, as: :json
      expect(response.parsed_body).to be_nil
    end
  end

  describe 'federation/stats' do
    it 'returns top subscribing/publishing instances and remainders' do
      Fabricate(:misskey_federation_instance_stat, domain: 'a.example', followers_count: 4, following_count: 0)
      Fabricate(:misskey_federation_instance_stat, domain: 'b.example', followers_count: 1, following_count: 7)

      post '/api/federation/stats', params: { limit: 1 }, as: :json

      expect(response).to have_http_status(200)
      body = response.parsed_body
      expect(body[:topSubInstances].first[:host]).to eq('a.example')
      expect(body[:topPubInstances].first[:host]).to eq('b.example')
      expect(body[:otherFollowersCount]).to eq(1)
      expect(body[:otherFollowingCount]).to eq(0)
    end
  end

  describe 'federation/users' do
    it 'returns remote users for the host' do
      Fabricate(:account, domain: 'remote.example', username: 'alice')

      post '/api/federation/users', params: { host: 'remote.example' }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body.first).to include(username: 'alice', host: 'remote.example')
    end
  end

  describe 'federation/following and followers' do
    it 'returns follow relationships for the host' do
      local = Fabricate(:account)
      remote = Fabricate(:account, domain: 'remote.example', username: 'bob')
      Fabricate(:follow, account: remote, target_account: local)

      post '/api/federation/following', params: { host: 'remote.example' }, as: :json
      expect(response).to have_http_status(200)
      expect(response.parsed_body.first).to include(followerId: MisskeyCompat::MiId.encode(remote.id))

      post '/api/federation/followers', params: { host: 'remote.example' }, as: :json
      expect(response.parsed_body).to be_empty
    end
  end

  describe 'federation/update-remote-user' do
    let(:remote) { Fabricate(:account, domain: 'remote.example', username: 'carol') }

    it 'requires authentication' do
      post '/api/federation/update-remote-user', params: { userId: MisskeyCompat::MiId.encode(remote.id) }, as: :json

      expect(response).to have_http_status(401)
    end

    it 'rejects users without the manage_federation privilege' do
      user = Fabricate(:user)
      token = Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read').token

      post '/api/federation/update-remote-user', params: { i: token, userId: MisskeyCompat::MiId.encode(remote.id) }, as: :json

      expect(response).to have_http_status(403)
    end

    it 'enqueues a refresh for a privileged user' do
      admin = Fabricate(:admin_user)
      token = Fabricate(:accessible_access_token, resource_owner_id: admin.id, scopes: 'read').token

      expect do
        post '/api/federation/update-remote-user', params: { i: token, userId: MisskeyCompat::MiId.encode(remote.id) }, as: :json
      end.to enqueue_sidekiq_job(RemoteAccountRefreshWorker).with(remote.id)

      expect(response).to have_http_status(204)
    end
  end
end
