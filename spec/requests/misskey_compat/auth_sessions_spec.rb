# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat legacy app authentication sessions' do
  let(:user)  { Fabricate(:user) }
  let(:token) { MisskeyCompat::MiAuth.issue_native_token(user).token }
  let(:application) do
    Doorkeeper::Application.create!(name: 'Legacy Client', redirect_uri: Doorkeeper.config.native_redirect_uri, scopes: 'misskey').tap do |app|
      app.create_misskey_app!(description: 'A client', permission: %w(read:account write:notes), callback_url: 'https://client.example/cb')
    end
  end

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  def generate_session
    post '/api/auth/session/generate', params: { appSecret: application.secret }, as: :json
    response.parsed_body
  end

  it 'runs the session flow from generation through native acceptance to a hashed access token' do
    session = generate_session
    expect(session[:url]).to eq("https://#{Rails.configuration.x.web_domain}/auth/#{session[:token]}")

    post '/api/auth/session/show', params: { i: token, token: session[:token] }, as: :json
    expect(response.parsed_body).to include(token: session[:token], app: include(name: 'Legacy Client', permission: %w(read:account write:notes), isAuthorized: false))

    post '/api/auth/session/userkey', params: { appSecret: application.secret, token: session[:token] }, as: :json
    expect(response.parsed_body[:error]).to include(code: 'PENDING_SESSION', id: '8c8a4145-02cc-4cca-8e66-29ba60445a8e')

    post '/api/auth/accept', params: { i: MisskeyCompat::MiAuth.issue_token(user, permission: 'write:account').token, token: session[:token] }, as: :json
    expect(response).to have_http_status(403)

    post '/api/auth/accept', params: { i: token, token: session[:token] }, as: :json
    expect(response).to have_http_status(204)

    post '/api/auth/session/userkey', params: { appSecret: application.secret, token: session[:token] }, as: :json
    access_token = response.parsed_body[:accessToken]
    expect(response.parsed_body[:user]).to include(id: MisskeyCompat::MiId.encode(user.account_id))

    issued = Doorkeeper::AccessToken.by_token(Digest::SHA256.hexdigest(access_token + application.secret))
    expect(issued).to have_attributes(application_id: application.id, resource_owner_id: user.id)
    expect(issued.misskey_access_grant.permissions).to eq(%w(read:account write:notes))
    expect(Doorkeeper::AccessToken.by_token(access_token)).to be_nil

    post '/api/auth/session/userkey', params: { appSecret: application.secret, token: session[:token] }, as: :json
    expect(response.parsed_body[:error]).to include(code: 'NO_SUCH_SESSION', id: '5b5a1503-8bc8-4bd0-8054-dc189e8cdcb3')
  end

  it 'revokes an app session by its original userkey value and removes its push subscriptions' do
    session = generate_session
    post '/api/auth/accept', params: { i: token, token: session[:token] }, as: :json
    post '/api/auth/session/userkey', params: { appSecret: application.secret, token: session[:token] }, as: :json
    access_token = response.parsed_body[:accessToken]
    issued = Doorkeeper::AccessToken.by_token(MisskeyCompat::MiAuth.app_token_hash(access_token, application))
    subscription = Fabricate(:web_push_subscription, user: user, access_token: issued)

    post '/api/i/revoke-token', params: { i: issued.token, token: access_token }, as: :json
    expect(response).to have_http_status(204)
    expect(issued.reload).to be_revoked
    expect(Web::PushSubscription.exists?(subscription.id)).to be(false)

    post '/api/i', params: { i: issued.token }, as: :json
    expect(response).to have_http_status(401)
  end

  it 'authenticates with the hashed token and lists the app as authorized' do
    raw = MisskeyCompat::MiAuth.issue_app_token(user, application)
    hashed = Digest::SHA256.hexdigest(raw + application.secret)

    post '/api/i', params: { i: hashed }, as: :json
    expect(response.parsed_body).to include(id: MisskeyCompat::MiId.encode(user.account_id))

    post '/api/i/authorized-apps', params: { i: token }, as: :json
    expect(response.parsed_body).to eq([{ 'id' => MisskeyCompat::MiId.encode(application.id), 'name' => 'Legacy Client', 'callbackUrl' => 'https://client.example/cb', 'permission' => %w(read:account write:notes), 'isAuthorized' => true }])

    post '/api/i/apps', params: { i: token }, as: :json
    expect(response.parsed_body.sole).to include(name: 'Legacy Client', permission: %w(read:account write:notes), description: 'A client')
  end

  it 'rejects unknown app secrets and expired sessions' do
    post '/api/auth/session/generate', params: { appSecret: 'wrong' }, as: :json
    expect(response.parsed_body[:error]).to include(code: 'NO_SUCH_APP', id: '92f93e63-428e-4f2f-a5a4-39e1407fe998')

    session = generate_session
    MisskeyAuthSession.find_by(token: session[:token]).update!(created_at: 1.hour.ago)

    post '/api/auth/session/show', params: { token: session[:token] }, as: :json
    expect(response.parsed_body[:error]).to include(code: 'NO_SUCH_SESSION', id: 'bd72c97d-eba7-4adb-a467-f171b8847250')
  end

  describe 'web approval page' do
    it 'requires sign-in, approves the session and redirects to the app callback with the session token' do
      session = generate_session

      get "/auth/#{session[:token]}"
      expect(response).to redirect_to(new_user_session_path)

      sign_in user
      get "/auth/#{session[:token]}"
      expect(response).to have_http_status(200)
      expect(response.body).to include('Legacy Client')

      post "/auth/#{session[:token]}"
      expect(response.body).to include("https://client.example/cb?token=#{session[:token]}")
      expect(MisskeyAuthSession.find_by(token: session[:token]).user).to eq(user)

      get "/auth/#{SecureRandom.uuid}"
      expect(response).to have_http_status(404)
    end
  end
end
