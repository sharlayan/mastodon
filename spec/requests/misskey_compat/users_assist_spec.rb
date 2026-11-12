# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat user assist endpoints' do
  let(:user)       { Fabricate(:user) }
  let(:account)    { user.account }
  let(:read_token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read').token }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  describe 'users/relation' do
    let(:followed) { Fabricate(:account) }
    let(:blocker)  { Fabricate(:account) }

    before do
      account.follow!(followed, reblogs: false)
      followed.follow!(account)
      account.mute!(followed)
      blocker.block!(account)
      account.block!(blocker)
    end

    it 'returns relations as an array for a single id or for an array of ids, with all-false entries for unknown ids' do
      post '/api/users/relation', params: { i: read_token, userId: MisskeyCompat::MiId.encode(followed.id) }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to eq([{
        id: MisskeyCompat::MiId.encode(followed.id),
        isFollowing: true,
        isFollowed: true,
        hasPendingFollowRequestFromYou: false,
        hasPendingFollowRequestToYou: false,
        isBlocking: false,
        isBlocked: false,
        isMuted: true,
        isRenoteMuted: true,
      }.deep_stringify_keys])

      ids = [blocker.id, followed.id, blocker.id, 1].map { |id| MisskeyCompat::MiId.encode(id) }
      post '/api/users/relation', params: { i: read_token, userId: ids }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to eq([ids[0], ids[1], ids[3]])
      expect(response.parsed_body.first).to include(isBlocking: true, isBlocked: true, isFollowing: false)
      expect(response.parsed_body.last.except(:id).values).to all(be(false))
    end

    it 'requires credentials and rejects malformed ids' do
      post '/api/users/relation', params: { userId: MisskeyCompat::MiId.encode(followed.id) }, as: :json

      expect(response).to have_http_status(401)

      post '/api/users/relation', params: { i: read_token, userId: [{ id: 1 }] }, as: :json

      expect(response).to have_http_status(400)
      expect(response.parsed_body.dig(:error, :code)).to eq('INVALID_PARAM')

      post '/api/users/relation', params: { i: read_token }, as: :json

      expect(response).to have_http_status(400)
    end
  end

  describe 'users/get-frequently-replied-users' do
    let(:author) { Fabricate(:account) }
    let(:often)  { Fabricate(:account) }
    let(:rarely) { Fabricate(:account) }
    let(:muted)  { Fabricate(:account) }

    def reply_to(target, visibility: :public, local_only: false)
      parent = Fabricate(:status, account: target)
      Fabricate(:status, account: author, thread: parent, visibility: visibility, local_only: local_only)
    end

    before do
      2.times { reply_to(often) }
      reply_to(rarely)
      reply_to(muted)
      3.times { reply_to(rarely, visibility: :direct) }
      2.times { reply_to(rarely, visibility: :private) }
      account.mute!(muted)
    end

    it 'weights public replies by the most replied account, skipping muted accounts and non-public replies' do
      post '/api/users/get-frequently-replied-users', params: { i: read_token, userId: MisskeyCompat::MiId.encode(author.id) }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body.map { |entry| [entry.dig(:user, :id), entry[:weight]] }).to eq([
                                                                                                   [MisskeyCompat::MiId.encode(often.id), 1.0],
                                                                                                   [MisskeyCompat::MiId.encode(rarely.id), 0.5],
                                                                                                 ])
      expect(response.parsed_body.first[:user]).to include(:isFollowing)

      post '/api/users/get-frequently-replied-users', params: { userId: MisskeyCompat::MiId.encode(author.id), limit: 2 }, as: :json

      expect(response.parsed_body.map { |entry| entry.dig(:user, :id) }).to eq([often, muted].map { |target| MisskeyCompat::MiId.encode(target.id) })
    end

    it 'hides local-only replies from anonymous viewers and returns NO_SUCH_USER for unknown users' do
      3.times { reply_to(muted, local_only: true) }

      post '/api/users/get-frequently-replied-users', params: { userId: MisskeyCompat::MiId.encode(author.id), limit: 1 }, as: :json

      expect(response.parsed_body.map { |entry| entry.dig(:user, :id) }).to eq([MisskeyCompat::MiId.encode(often.id)])

      post '/api/users/get-frequently-replied-users', params: { userId: MisskeyCompat::MiId.encode(1) }, as: :json

      expect(response).to have_http_status(404)
      expect(response.parsed_body.dig(:error, :code)).to eq('NO_SUCH_USER')
    end
  end

  describe 'users/recommendation' do
    let!(:featured) { Fabricate(:account, username: 'featured', discoverable: true) }
    let!(:followed) { Fabricate(:account, username: 'followed', discoverable: true) }

    before do
      Setting.bootstrap_timeline_accounts = 'featured, followed'
      account.follow!(followed)
    end

    it 'returns Mastodon follow suggestions as detailed users, without accounts already followed' do
      post '/api/users/recommendation', params: { i: read_token, limit: 5 }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to eq([MisskeyCompat::MiId.encode(featured.id)])
      expect(response.parsed_body.first).to include(isFollowing: false)

      post '/api/users/recommendation', params: { i: read_token, offset: 1 }, as: :json

      expect(response.parsed_body).to eq([])

      post '/api/users/recommendation', as: :json

      expect(response).to have_http_status(401)
    end
  end
end
