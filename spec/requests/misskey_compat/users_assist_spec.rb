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
end
