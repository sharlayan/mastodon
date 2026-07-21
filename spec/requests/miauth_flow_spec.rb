# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'MiAuth web flow' do
  let(:user) { Fabricate(:user) }
  let(:session_id) { SecureRandom.uuid }
  let(:callback) { 'flare://Callback/SignIn/Misskey' }
  let(:rate_limiter) { instance_double(RateLimiter, record!: true) }

  before do
    Setting.misskey_compat_enabled = true
    allow(RateLimiter).to receive(:new).and_return(rate_limiter)
    RedisConnection.with { |redis| redis.del(MisskeyCompat::MiAuth.redis_key(session_id)) }
  end

  after do
    RedisConnection.with { |redis| redis.del(MisskeyCompat::MiAuth.redis_key(session_id)) }
    Setting.misskey_compat_enabled = false
  end

  context 'when authenticated' do
    before { sign_in user }

    it 'renders the approval page' do
      get "/miauth/#{session_id}", params: { name: 'Flare', callback: callback }
      expect(response).to have_http_status(200)
    end

    it 'renders the completion page that navigates to the deeplink callback with session on approve' do
      post "/miauth/#{session_id}", params: { name: 'Flare', callback: callback }
      expect(response).to have_http_status(200)
      expect(response.body).to include("#{callback}?session=#{session_id}")
    end

    it 'allows the issued token to be claimed only once' do
      token = MisskeyCompat::MiAuth.issue_token(user, permission: 'read:account,write:notes', name: 'Flare', callback: callback)
      RedisConnection.with { |redis| redis.set(MisskeyCompat::MiAuth.redis_key(session_id), token.token, ex: MisskeyCompat::MiAuth::SESSION_TTL.to_i) }

      post "/api/miauth/#{session_id}/check", as: :json
      expect(response).to have_http_status(200)
      expect(response.parsed_body['ok']).to be true

      post "/api/miauth/#{session_id}/check", as: :json
      expect(response).to have_http_status(200)
      expect(response.parsed_body).to eq('ok' => false)
    end

    it 'limits the token to requested permissions and gives it a finite lifetime' do
      post "/miauth/#{session_id}", params: { name: 'Reader', callback: callback, permission: 'read:account' }

      token = Doorkeeper::AccessToken.where(resource_owner_id: user.id).order(id: :desc).first
      expect(token.scopes.to_s).to eq('read')
      expect(token.expires_in).to eq(MisskeyCompat::MiAuth::TOKEN_TTL.to_i)
    end

    it 'does not promote an unknown permission to the coarse write scope' do
      token = MisskeyCompat::MiAuth.issue_token(user, permission: 'write:unknown')

      expect(token.scopes.to_s).to eq('read')
    end

    it 'keeps different clients in individually revocable applications' do
      first = MisskeyCompat::MiAuth.issue_token(user, name: 'First', callback: 'first://callback')
      second = MisskeyCompat::MiAuth.issue_token(user, name: 'Second', callback: 'second://callback')

      expect(first.application_id).to_not eq(second.application_id)
    end

    it 'recognizes legacy non-expiring full-scope tokens for rejection' do
      application = Fabricate(:application, name: MisskeyCompat::MiAuth::APP_NAME, scopes: MisskeyCompat::MiAuth::SCOPES)
      token = Fabricate(:accessible_access_token, application: application, resource_owner_id: user.id, scopes: MisskeyCompat::MiAuth::SCOPES, expires_in: nil)

      expect(MisskeyCompat::MiAuth.legacy_token?(token)).to be true

      post '/api/i', params: { i: token.token }, as: :json
      expect(response).to have_http_status(401)
    end

    it 'ignores unsafe callback schemes on approve' do
      post "/miauth/#{session_id}", params: { name: 'Flare', callback: 'javascript:alert(1)' }
      expect(response).to have_http_status(200)
      expect(response.body).to_not include('javascript:alert(1)')
    end

    it 'rejects session identifiers with insufficient entropy' do
      get '/miauth/12345678', params: { name: 'Flare', callback: callback }

      expect(response).to have_http_status(404)
    end
  end

  describe 'detailed user serialization for Flare' do
    let(:required_fields) do
      %i(id username createdAt isLocked isSilenced isSuspended fields followersCount followingCount notesCount pinnedNoteIds pinnedNotes publicReactions)
    end

    it 'includes every non-nullable field the Flare Misskey User model requires' do
      payload = MisskeyCompat::UserSerializer.serialize(user.account, detailed: true)
      expect(required_fields - payload.keys).to be_empty
    end
  end
end
