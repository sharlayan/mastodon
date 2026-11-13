# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat apps and access tokens' do
  let(:user)  { Fabricate(:user, password: 'correct horse') }
  let(:token) { MisskeyCompat::MiAuth.issue_native_token(user).token }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  def create_app(**params)
    post '/api/app/create', params: { name: 'Legacy Client', description: 'A client', permission: %w(account-read write:notes), callbackUrl: 'https://client.example/cb' }.merge(params), as: :json
    response.parsed_body
  end

  describe 'apps' do
    it 'creates a Doorkeeper application with Misskey permissions and returns its secret once' do
      created = create_app(i: token)
      application = Doorkeeper::Application.find(MisskeyCompat::MiId.decode(created[:id]))

      expect(created).to eq({ 'id' => MisskeyCompat::MiId.encode(application.id), 'name' => 'Legacy Client', 'callbackUrl' => 'https://client.example/cb', 'permission' => %w(read:account write:notes), 'secret' => application.secret })
      expect(application).to have_attributes(owner: user, scopes: Doorkeeper::OAuth::Scopes.from_string('misskey'))
      expect(application.misskey_app).to have_attributes(description: 'A client', permission: %w(read:account write:notes))

      create_app(permission: 'read:account')
      expect(response).to have_http_status(400)

      expect(create_app(i: 'invalid')).to include('error')
      expect(response).to have_http_status(401)
    end

    it 'shows an app, includes the secret only for its owner native session, and lists my apps' do
      app_id = create_app(i: token)[:id]
      create_app

      post '/api/app/show', params: { appId: app_id }, as: :json
      expect(response.parsed_body).to eq({ 'id' => app_id, 'name' => 'Legacy Client', 'callbackUrl' => 'https://client.example/cb', 'permission' => %w(read:account write:notes) })

      post '/api/app/show', params: { i: token, appId: app_id }, as: :json
      expect(response.parsed_body).to include(secret: be_present, isAuthorized: false)

      post '/api/app/show', params: { i: MisskeyCompat::MiAuth.issue_token(user, permission: 'read:account').token, appId: app_id }, as: :json
      expect(response.parsed_body).to_not have_key(:secret)

      post '/api/app/show', params: { appId: MisskeyCompat::MiId.encode(MisskeyCompat::MiAuth.application(name: 'x').id) }, as: :json
      expect(response).to have_http_status(404)
      expect(response.parsed_body[:error]).to include(code: 'NO_SUCH_APP', id: 'dce83913-2dc6-4093-8a7b-71dbb11718a3')

      post '/api/my/apps', params: { i: MisskeyCompat::MiAuth.issue_token(user, permission: 'read:account').token }, as: :json
      expect(response.parsed_body.pluck(:id)).to eq([app_id])
    end
  end

  describe 'access tokens' do
    let!(:miauth) { MisskeyCompat::MiAuth.issue_token(user, permission: 'read:account', name: 'A very long third-party client name', description: 'Desc', icon_url: 'https://client.example/icon.png') }

    it 'lists the caller MiAuth tokens without the native sign-in token and only for the native session' do
      token
      MisskeyCompat::MiAuth.issue_token(Fabricate(:user), permission: 'read:account')

      post '/api/i/apps', params: { i: miauth.token }, as: :json
      expect(response).to have_http_status(403)

      post '/api/i/apps', params: { i: token, sort: '+createdAt' }, as: :json
      expect(response.parsed_body).to eq([{
        'id' => MisskeyCompat::MiId.encode(miauth.id),
        'name' => 'A very long third-party client name',
        'createdAt' => miauth.created_at.iso8601,
        'lastUsedAt' => miauth.reload.last_used_at.iso8601,
        'permission' => %w(read:account),
        'iconUrl' => 'https://client.example/icon.png',
        'description' => 'Desc',
      }])

      post '/api/i/authorized-apps', params: { i: token }, as: :json
      expect(response.parsed_body).to eq([])
    end

    it 'revokes the caller tokens by id or value and ignores other users tokens' do
      others = MisskeyCompat::MiAuth.issue_token(Fabricate(:user), permission: 'read:account')
      Fabricate(:web_push_subscription, user: user, access_token: miauth)

      post '/api/i/revoke-token', params: { i: token, tokenId: MisskeyCompat::MiId.encode(others.id) }, as: :json
      expect(response).to have_http_status(204)
      expect(others.reload).to_not be_revoked

      post '/api/i/revoke-token', params: { i: token, tokenId: MisskeyCompat::MiId.encode(miauth.id) }, as: :json
      expect(miauth.reload).to be_revoked
      expect(Web::PushSubscription.where(access_token_id: miauth.id)).to be_empty

      second = MisskeyCompat::MiAuth.issue_token(user, permission: 'read:account')
      post '/api/i/revoke-token', params: { i: token, token: second.token }, as: :json
      expect(second.reload).to be_revoked
    end

    it 'regenerates the native token by revoking every native sign-in token after the password check' do
      other_native = MisskeyCompat::MiAuth.issue_native_token(user)

      post '/api/i/regenerate-token', params: { i: token, password: 'wrong' }, as: :json
      expect(response).to have_http_status(500)

      post '/api/i/regenerate-token', params: { i: token, password: 'correct horse' }, as: :json
      expect(response).to have_http_status(204)
      expect(Doorkeeper::AccessToken.by_token(token)).to be_revoked
      expect(other_native.reload).to be_revoked
      expect(miauth.reload).to_not be_revoked
    end

    it 'generates a MiAuth token from the native session and hands it to the session check' do
      session = SecureRandom.uuid

      post '/api/miauth/gen-token', params: { i: token, session: session, name: 'Client', description: 'Desc', iconUrl: nil, permission: %w(read:account write:notes unknown) }, as: :json
      generated = Doorkeeper::AccessToken.by_token(response.parsed_body[:token])
      expect(generated.misskey_access_grant).to have_attributes(permissions: %w(read:account write:notes), name: 'Client', description: 'Desc', native_user_token: false)

      post "/api/miauth/#{session}/check", as: :json
      expect(response.parsed_body).to include(ok: true, token: generated.token)

      post '/api/miauth/gen-token', params: { i: token, permission: [] }, as: :json
      expect(response).to have_http_status(400)
    end
  end
end
