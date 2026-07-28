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
    it 'requires credentials' do
      post '/api/sw/register', params: { endpoint: endpoint, auth: auth, publickey: publickey }, as: :json

      expect(response).to have_http_status(401)
    end

    it 'rejects a request without the push keys' do
      post '/api/sw/register', params: register_params(auth: '', publickey: ''), as: :json

      expect(response).to have_http_status(400)
      expect(response.parsed_body.dig(:error, :code)).to eq('INVALID_PARAM')
    end

    it 'creates the subscription and echoes the endpoint unchanged' do
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
    end

    it 'reports an existing registration instead of duplicating it' do
      post '/api/sw/register', params: register_params, as: :json
      post '/api/sw/register', params: register_params, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:state]).to eq('already-subscribed')
      expect(Web::PushSubscription.where(user_id: user.id, endpoint: endpoint).count).to eq(1)
    end
  end

  describe 'POST /api/sw/show-registration' do
    it 'returns null when nothing is registered for the endpoint' do
      post '/api/sw/show-registration', params: { i: token.token, endpoint: endpoint }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to be_nil
    end

    it 'returns the registration for a known endpoint' do
      post '/api/sw/register', params: register_params, as: :json
      post '/api/sw/show-registration', params: { i: token.token, endpoint: endpoint }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to include(endpoint: endpoint, userId: MisskeyCompat::MiId.encode(account.id))
    end
  end

  describe 'POST /api/sw/unregister' do
    it 'requires the endpoint' do
      post '/api/sw/unregister', params: { i: token.token }, as: :json

      expect(response).to have_http_status(400)
      expect(response.parsed_body.dig(:error, :code)).to eq('INVALID_PARAM')
    end

    it 'removes the subscription' do
      post '/api/sw/register', params: register_params, as: :json

      expect { post '/api/sw/unregister', params: { i: token.token, endpoint: endpoint }, as: :json }
        .to change { Web::PushSubscription.where(user_id: user.id, endpoint: endpoint).count }.from(1).to(0)
      expect(response).to have_http_status(204)
    end

    it 'succeeds when the subscription is already gone' do
      post '/api/sw/unregister', params: { i: token.token, endpoint: endpoint }, as: :json

      expect(response).to have_http_status(204)
    end
  end
end
