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
      post "/miauth/#{session_id}", params: { name: 'Flare', callback: callback, permission: 'read:account,write:notes' }
      expect(response).to have_http_status(200)

      post "/api/miauth/#{session_id}/check", as: :json
      expect(response).to have_http_status(200)
      expect(response.parsed_body['ok']).to be true
      expect(response.parsed_body['token']).to be_present

      post "/api/miauth/#{session_id}/check", as: :json
      expect(response).to have_http_status(200)
      expect(response.parsed_body).to eq('ok' => false)
    end

    it 'stores exact requested permissions behind a dedicated finite-lifetime token' do
      post "/miauth/#{session_id}", params: { name: 'Reader', callback: callback, permission: 'read:account' }

      token = Doorkeeper::AccessToken.where(resource_owner_id: user.id).order(id: :desc).first
      expect(token.scopes.to_s).to eq(MisskeyCompat::MiAuth::TOKEN_SCOPE)
      expect(token.expires_in).to eq(MisskeyCompat::MiAuth::TOKEN_TTL.to_i)
      expect(token.misskey_access_grant.permissions).to eq(['read:account'])
    end

    it 'drops unknown permissions instead of promoting them' do
      token = MisskeyCompat::MiAuth.issue_token(user, permission: 'write:unknown')

      expect(token.scopes.to_s).to eq(MisskeyCompat::MiAuth::TOKEN_SCOPE)
      expect(token.misskey_access_grant.permissions).to be_empty
    end

    it 'keeps different clients in individually revocable applications' do
      first = MisskeyCompat::MiAuth.issue_token(user, name: 'First', callback: 'first://callback')
      second = MisskeyCompat::MiAuth.issue_token(user, name: 'Second', callback: 'second://callback')

      expect(first.application_id).to_not eq(second.application_id)
    end

    it 'converts an existing coarse-scope client application to the isolated scope' do
      existing = MisskeyCompat::MiAuth.application(name: 'Existing', callback: callback)
      existing.update!(scopes: 'read write follow push')

      token = MisskeyCompat::MiAuth.issue_token(user, name: 'Existing', callback: callback, permission: 'read:account')

      expect(token.application_id).to eq(existing.id)
      expect(existing.reload.scopes.to_s).to eq(MisskeyCompat::MiAuth::TOKEN_SCOPE)
    end

    it 'recognizes legacy non-expiring full-scope tokens for rejection' do
      application = Fabricate(:application, name: MisskeyCompat::MiAuth::APP_NAME, scopes: 'read write follow push')
      token = Fabricate(:accessible_access_token, application: application, resource_owner_id: user.id, scopes: 'read write follow push', expires_in: nil)

      expect(MisskeyCompat::MiAuth.legacy_token?(token)).to be true

      post '/api/i', params: { i: token.token }, as: :json
      expect(response).to have_http_status(401)
    end

    it 'enforces the exact permission on Misskey-compatible endpoints' do
      token = MisskeyCompat::MiAuth.issue_token(user, permission: 'read:account,write:notes')
      blocked = Fabricate(:account)

      post '/api/notes/create', params: { i: token.token, text: 'allowed note' }, as: :json
      expect(response).to have_http_status(200)

      post '/api/blocking/create', params: { i: token.token, userId: blocked.id.to_s }, as: :json
      expect(response).to have_http_status(403)
      expect(user.account.blocking?(blocked)).to be false
    end

    it 'does not let a general account-read permission expose specialized collections' do
      token = MisskeyCompat::MiAuth.issue_token(user, permission: 'read:account')

      post '/api/i', params: { i: token.token }, as: :json
      expect(response).to have_http_status(200)

      post '/api/blocking/list', params: { i: token.token }, as: :json
      expect(response).to have_http_status(403)
    end

    it 'cannot use a MiAuth token as a general Mastodon write token' do
      token = MisskeyCompat::MiAuth.issue_token(user, permission: 'write:notes')

      post '/api/v1/statuses', params: { status: 'scope isolation' }, headers: { 'Authorization' => "Bearer #{token.token}" }

      expect(response).to have_http_status(403)
      expect(user.account.statuses.where(text: 'scope isolation')).to_not exist
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

    it 'includes avatar decoration display effects' do
      decoration = Fabricate(:avatar_decoration)
      user.account.update!(avatar_decorations: [{ id: decoration.id, scale: 1.25, opacity: 0.6 }])
      previous_setting = Setting.avatar_decorations_enabled
      Setting.avatar_decorations_enabled = true

      payload = MisskeyCompat::UserSerializer.serialize(user.account, detailed: true)

      expect(payload[:avatarDecorations]).to contain_exactly(include(scale: 1.25, opacity: 0.6))
    ensure
      Setting.avatar_decorations_enabled = previous_setting
    end
  end
end
