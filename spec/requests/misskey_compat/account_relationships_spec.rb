# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat account relationship endpoints' do
  let(:user)        { Fabricate(:user) }
  let(:account)     { user.account }
  let(:target)      { Fabricate(:account) }
  let(:other)       { Fabricate(:account) }
  let(:read_token)  { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read').token }
  let(:write_token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'write').token }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  describe 'blocking endpoints' do
    it 'lists only blocks owned by the authenticated account with MiId identifiers' do
      block = account.block_relationships.create!(target_account: target)
      other.block!(account)

      post '/api/blocking/list', params: { i: read_token }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to contain_exactly(
        include(
          id: MisskeyCompat::MiId.encode(block.id),
          blockeeId: MisskeyCompat::MiId.encode(target.id)
        )
      )
    end

    it 'rejects writes made with a read-only token' do
      post '/api/blocking/create', params: { i: read_token, userId: target.id }, as: :json

      expect(response).to have_http_status(403)
      expect(account.blocking?(target)).to be(false)
    end

    it 'creates and removes a block using a MiId userId' do
      user_id = MisskeyCompat::MiId.encode(target.id)

      post '/api/blocking/create', params: { i: write_token, userId: user_id }, as: :json
      expect(response).to have_http_status(200)
      expect(account.blocking?(target)).to be(true)

      post '/api/blocking/delete', params: { i: write_token, userId: user_id }, as: :json
      expect(response).to have_http_status(200)
      expect(account.blocking?(target)).to be(false)
    end
  end

  describe 'following endpoints' do
    it 'lists only follow requests addressed to the authenticated account' do
      request = Fabricate(:follow_request, account: target, target_account: account)
      Fabricate(:follow_request, account: other, target_account: target)

      post '/api/following/requests/list', params: { i: read_token }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to contain_exactly(
        include(
          id: MisskeyCompat::MiId.encode(request.id),
          follower: include(id: MisskeyCompat::MiId.encode(target.id)),
          followee: include(id: MisskeyCompat::MiId.encode(account.id))
        )
      )
    end

    it 'returns NOT_FOLLOWING when updating a missing relationship' do
      post '/api/following/update', params: { i: write_token, userId: MisskeyCompat::MiId.encode(target.id), notify: 'normal' }, as: :json

      expect(response).to have_http_status(400)
      expect(response.parsed_body.dig(:error, :code)).to eq('NOT_FOLLOWING')
    end

    it 'updates notifications on an owned follow relationship' do
      follow = Fabricate(:follow, account: account, target_account: target, notify: false)

      post '/api/following/update', params: { i: write_token, userId: MisskeyCompat::MiId.encode(target.id), notify: 'normal' }, as: :json

      expect(response).to have_http_status(200)
      expect(follow.reload.notify).to be(true)
    end
  end

  describe 'mute endpoints' do
    it 'lists only mutes owned by the authenticated account with MiId identifiers' do
      mute = account.mute_relationships.create!(target_account: target)
      other.mute!(account)

      post '/api/mute/list', params: { i: read_token }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to contain_exactly(
        include(
          id: MisskeyCompat::MiId.encode(mute.id),
          expiresAt: nil,
          muteeId: MisskeyCompat::MiId.encode(target.id)
        )
      )
    end

    it 'creates and removes a mute using a MiId userId' do
      user_id = MisskeyCompat::MiId.encode(target.id)

      post '/api/mute/create', params: { i: write_token, userId: user_id, notifications: false }, as: :json
      expect(response).to have_http_status(204)
      expect(account.muting?(target)).to be(true)
      expect(account.mute_relationships.find_by(target_account: target)).to have_attributes(expires_at: nil, hide_notifications: false)

      post '/api/mute/delete', params: { i: write_token, userId: user_id }, as: :json
      expect(response).to have_http_status(204)
      expect(account.muting?(target)).to be(false)
    end

    it 'stores a future expiresAt and returns its ISO date in mute/list' do
      expires_at = 1.hour.from_now.to_i * 1000

      post '/api/mute/create', params: { i: write_token, userId: MisskeyCompat::MiId.encode(target.id), expiresAt: expires_at }, as: :json

      expect(response).to have_http_status(204)
      mute = account.mute_relationships.find_by!(target_account: target)
      expect(mute.expires_at).to be_within(1.second).of(Time.zone.at(expires_at / 1000.0))

      post '/api/mute/list', params: { i: read_token }, as: :json

      expect(response.parsed_body).to contain_exactly(include(expiresAt: mute.expires_at.utc.iso8601(3)))
    end

    it 'does not turn a subsecond future expiresAt into an indefinite mute' do
      travel_to(Time.current.change(usec: 0)) do
        expires_at = (Time.now.utc.to_f * 1000).floor + 500

        post '/api/mute/create', params: { i: write_token, userId: MisskeyCompat::MiId.encode(target.id), expiresAt: expires_at }, as: :json

        expect(response).to have_http_status(204)
        expect(account.mute_relationships.find_by!(target_account: target).expires_at).to be_present
      end
    end

    it 'treats a past expiresAt as a successful no-op' do
      post '/api/mute/create', params: { i: write_token, userId: MisskeyCompat::MiId.encode(target.id), expiresAt: 1.minute.ago.to_i * 1000 }, as: :json

      expect(response).to have_http_status(204)
      expect(account.muting?(target)).to be(false)
    end

    it 'rejects a non-integer expiresAt' do
      post '/api/mute/create', params: { i: write_token, userId: MisskeyCompat::MiId.encode(target.id), expiresAt: 'tomorrow' }, as: :json

      expect(response).to have_http_status(400)
      expect(response.parsed_body.dig(:error, :code)).to eq('INVALID_PARAM')
      expect(account.muting?(target)).to be(false)
    end

    it 'toggles and lists renote mutes only for owned follows' do
      follow = Fabricate(:follow, account: account, target_account: target, show_reblogs: true)
      Fabricate(:follow, account: other, target_account: account, show_reblogs: false)
      user_id = MisskeyCompat::MiId.encode(target.id)

      post '/api/renote-mute/create', params: { i: write_token, userId: user_id }, as: :json
      expect(response).to have_http_status(204)
      expect(follow.reload.show_reblogs).to be(false)

      post '/api/renote-mute/list', params: { i: read_token }, as: :json
      expect(response.parsed_body).to contain_exactly(include(muteeId: user_id))

      post '/api/renote-mute/delete', params: { i: write_token, userId: user_id }, as: :json
      expect(response).to have_http_status(204)
      expect(follow.reload.show_reblogs).to be(true)
    end
  end
end
