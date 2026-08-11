# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'MiAuth web flow' do
  let(:user) { Fabricate(:user) }
  let(:session_id) { SecureRandom.uuid }
  let(:callback) { 'https://client.example/callback' }
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

    it 'renders the completion page that navigates to the HTTPS callback with session on approve' do
      post "/miauth/#{session_id}", params: { name: 'Flare', callback: callback }
      expect(response).to have_http_status(200)
      expect(response.body).to include("#{callback}?session=#{session_id}")
    end

    it 'allows native application callback schemes' do
      native_callbacks = ['aria://aria/miauth', 'flare://Callback/SignIn/Misskey', 'another-client+auth://callback/miauth']

      native_callbacks.each do |native_callback|
        get "/miauth/#{session_id}", params: { name: 'Native client', callback: native_callback }
        expect(response).to have_http_status(200)

        post "/miauth/#{session_id}", params: { name: 'Native client', callback: native_callback }
        expect(response).to have_http_status(200)
        expect(response.body).to include("#{native_callback}?session=#{session_id}")
      end
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

    it 'lists issued client applications in Mastodon authorized-app settings' do
      post "/miauth/#{session_id}", params: { name: 'Visible client', callback: callback }
      token = Doorkeeper::AccessToken.where(resource_owner_id: user.id).order(id: :desc).first
      application = token.application

      expect(response.body).to include(oauth_authorized_applications_path)

      get oauth_authorized_applications_path
      expect(response).to have_http_status(200)
      expect(response.body).to include(application.name)

      delete oauth_authorized_application_path(application)
      expect(token.reload.revoked_at).to be_present
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

    it 'rejects unsafe callback schemes on approve' do
      ['http://client.example/callback', 'javascript:alert(1)', 'file:///tmp/token', 'data:text/plain,token', 'mailto:client@example.com', 'tel:1234', 'vbscript:alert(1)'].each do |unsafe_callback|
        post "/miauth/#{session_id}", params: { name: 'Flare', callback: unsafe_callback }
        expect(response).to have_http_status(400)
        expect(response.body).to_not include(unsafe_callback)
      end
    end

    it 'enforces both issuance limits and rolls back a successful counter when the other limit rejects' do
      expect(RateLimiter::FAMILIES[:misskey_miauth_hourly]).to include(limit: 10, period: 1.hour)
      expect(RateLimiter::FAMILIES[:misskey_miauth_daily]).to include(limit: 30, period: 24.hours)

      calls = 0
      allow(rate_limiter).to receive(:record!) do
        calls += 1
        raise Mastodon::RateLimitExceededError if calls == 2
      end
      allow(rate_limiter).to receive(:rollback!).and_return(true)
      allow(MisskeyCompat::MiAuth).to receive(:issue_token).and_call_original

      post "/miauth/#{session_id}", params: { name: 'Limited', callback: callback }

      expect(calls).to eq(2)
      expect(response).to have_http_status(429)
      expect(rate_limiter).to have_received(:rollback!)
      expect(MisskeyCompat::MiAuth).to_not have_received(:issue_token)
    end

    it 'rejects session identifiers with insufficient entropy' do
      get '/miauth/12345678', params: { name: 'Flare', callback: callback }

      expect(response).to have_http_status(404)
    end
  end

  it 'does not return a claimed token for an account that became unavailable' do
    sign_in user
    post "/miauth/#{session_id}", params: { name: 'Flare', callback: callback }
    user.account.update!(suspended_at: Time.current)

    post "/api/miauth/#{session_id}/check", as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body).to eq('ok' => false)
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
