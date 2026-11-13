# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat service worker endpoints' do
  let(:user)    { Fabricate(:user) }
  let(:account) { user.account }
  let(:token)   { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write') }
  let(:endpoint) { 'https://ntfy.example/upABCDEF?up=1' }
  let(:auth)     { 'YXV0aC1zZWNyZXQ' }
  let(:publickey) { 'BOSIjzD4yKwMdDWTbuNy7hICylPQ9kwN-kR7APV6wJo-tVtO0L7A-0tb6LcmZx2hS6SETEDp2fCKdSJdomXZz-I' }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  def register_params(overrides = {})
    { i: token.token, endpoint: endpoint, auth: auth, publickey: publickey }.merge(overrides)
  end

  describe 'POST /api/sw/register' do
    it 'requires credentials and rejects a request without the push keys' do
      post '/api/sw/register', params: { endpoint: endpoint, auth: auth, publickey: publickey }, as: :json

      expect(response).to have_http_status(401)

      post '/api/sw/register', params: register_params(auth: '', publickey: ''), as: :json

      expect(response).to have_http_status(400)
      expect(response.parsed_body.dig(:error, :code)).to eq('INVALID_PARAM')
    end

    it 'creates the subscription, echoes the endpoint unchanged, and reports a repeated registration instead of duplicating it' do
      post '/api/sw/register', params: register_params, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to include(
        state: 'subscribed',
        userId: MisskeyCompat::MiId.encode(account.id),
        endpoint: endpoint,
        sendReadMessage: false
      )
      expect(response.parsed_body[:key]).to eq(Rails.configuration.x.vapid.public_key)

      subscription = Web::PushSubscription.find_by(user_id: user.id, endpoint: endpoint)
      expect(subscription).to have_attributes(key_auth: auth, key_p256dh: publickey, access_token_id: token.id)
      expect(subscription.data['compat']).to eq('misskey')

      post '/api/sw/register', params: register_params, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:state]).to eq('already-subscribed')
      expect(Web::PushSubscription.where(user_id: user.id, endpoint: endpoint).count).to eq(1)
    end
  end

  describe 'POST /api/sw/show-registration' do
    it 'returns null when nothing is registered for the endpoint and the registration for a known endpoint' do
      post '/api/sw/show-registration', params: { i: token.token, endpoint: endpoint }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to be_nil

      post '/api/sw/register', params: register_params, as: :json
      post '/api/sw/show-registration', params: { i: token.token, endpoint: endpoint }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to include(endpoint: endpoint, userId: MisskeyCompat::MiId.encode(account.id))
    end
  end

  describe 'POST /api/sw/unregister' do
    it 'checks both subscription keys and removes all matching accounts only without credentials' do
      other_user = Fabricate(:user)
      other_token = Fabricate(:accessible_access_token, resource_owner_id: other_user.id, scopes: 'read write')
      post '/api/sw/register', params: register_params, as: :json
      post '/api/sw/register', params: register_params(i: other_token.token), as: :json
      keys = register_params.except(:i)

      [keys.except(:auth), keys.merge(auth: []), keys.merge(publickey: nil)].each do |invalid|
        post '/api/sw/unregister', params: invalid, as: :json
        expect(response).to have_http_status(400)
      end

      [keys.merge(auth: 'wrong'), keys.merge(publickey: 'wrong')].each do |invalid|
        expect { post '/api/sw/unregister', params: invalid, as: :json }.to_not change(Web::PushSubscription, :count)
        expect(response).to have_http_status(204)
      end

      post '/api/sw/unregister', params: keys.merge(i: 'invalid'), as: :json
      expect(response).to have_http_status(401)

      expect { post '/api/sw/unregister', params: keys.merge(i: token.token), as: :json }
        .to change { Web::PushSubscription.where(user_id: user.id).count }.from(1).to(0)
        .and(not_change { Web::PushSubscription.where(user_id: other_user.id).count })

      expect { post '/api/sw/unregister', params: keys, as: :json }
        .to change { Web::PushSubscription.where(user_id: other_user.id).count }.from(1).to(0)
      expect(response).to have_http_status(204)
    end

    it 'limits anonymous subscription removal attempts' do
      limiter = instance_double(RateLimiter)
      allow(RateLimiter).to receive(:new).with(anything, family: :misskey_compat_push_unregister).and_return(limiter)
      allow(limiter).to receive(:record!).and_raise(Mastodon::RateLimitExceededError)
      post '/api/sw/unregister', params: register_params.except(:i), as: :json
      expect(response).to have_http_status(429)
    end

    it 'removes the subscription for the current session without an endpoint' do
      other_token = Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write')
      other_endpoint = 'https://ntfy.example/upOTHER?up=1'

      post '/api/sw/register', params: register_params, as: :json
      post '/api/sw/register', params: register_params(endpoint: other_endpoint, i: other_token.token), as: :json

      expect { post '/api/sw/unregister', params: { i: token.token }, as: :json }
        .to change { Web::PushSubscription.where(access_token_id: token.id).count }.from(1).to(0)
        .and(not_change { Web::PushSubscription.where(access_token_id: other_token.id).count })
      expect(response).to have_http_status(204)
    end

    it 'removes the subscription and succeeds when it is already gone or the current session has none' do
      post '/api/sw/register', params: register_params, as: :json

      expect { post '/api/sw/unregister', params: { i: token.token, endpoint: endpoint }, as: :json }
        .to change { Web::PushSubscription.where(user_id: user.id, endpoint: endpoint).count }.from(1).to(0)
      expect(response).to have_http_status(204)

      post '/api/sw/unregister', params: { i: token.token, endpoint: endpoint }, as: :json

      expect(response).to have_http_status(204)

      post '/api/sw/unregister', params: { i: token.token }, as: :json

      expect(response).to have_http_status(204)
    end
  end

  describe 'POST /api/sw/update-registration' do
    let(:native_token) { MisskeyCompat::MiAuth.issue_native_token(user).token }

    it 'stores sendReadMessage on the caller subscription and reports it from every registration endpoint' do
      post '/api/sw/update-registration', params: { i: native_token, endpoint: endpoint, sendReadMessage: true }, as: :json
      expect(response).to have_http_status(404)
      expect(response.parsed_body.dig(:error, :code)).to eq('NO_SUCH_REGISTRATION')

      post '/api/sw/register', params: register_params, as: :json

      post '/api/sw/update-registration', params: { i: token.token, endpoint: endpoint, sendReadMessage: true }, as: :json
      expect(response).to have_http_status(403)

      post '/api/sw/update-registration', params: { i: native_token, endpoint: endpoint, sendReadMessage: true }, as: :json
      expect(response.parsed_body).to eq({ 'userId' => MisskeyCompat::MiId.encode(account.id), 'endpoint' => endpoint, 'sendReadMessage' => true })

      post '/api/sw/show-registration', params: { i: token.token, endpoint: endpoint }, as: :json
      expect(response.parsed_body).to include(sendReadMessage: true)

      post '/api/sw/register', params: register_params, as: :json
      expect(response.parsed_body).to include(state: 'already-subscribed', sendReadMessage: true)
    end
  end
end
