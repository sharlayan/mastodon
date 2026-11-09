# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat signin-flow endpoint' do
  before do
    Setting.misskey_compat_enabled = true
    Setting.misskey_compat_signin_flow_enabled = true
    Setting.misskey_compat_signin_flow_allowed_origins = ''
    host! 'local.test'
    https!
  end

  after do
    Setting.misskey_compat_enabled = false
    Setting.misskey_compat_signin_flow_enabled = false
    Setting.misskey_compat_signin_flow_allowed_origins = ''
  end

  let(:username) { 'alice' }
  let(:email) { 'alice@example.com' }
  let(:password) { 'wonderland-123' }
  let(:origin_headers) { { 'HTTP_ORIGIN' => 'https://local.test' } }
  let!(:user) { Fabricate(:user, email: email, password: password, account_attributes: { username: username }) }

  describe 'POST /api/signin-flow' do
    it 'is not routed as an available endpoint when either the compat gate or the dedicated signin-flow gate is off' do
      Setting.misskey_compat_enabled = false
      post '/api/signin-flow', params: { username: email, password: password }, headers: origin_headers, as: :json

      expect(response).to have_http_status(404)
      expect(response.parsed_body.dig('error', 'code')).to eq('ENDPOINT_DISABLED')

      Setting.misskey_compat_enabled = true
      Setting.misskey_compat_signin_flow_enabled = false
      post '/api/signin-flow', params: { username: email, password: password }, headers: origin_headers, as: :json

      expect(response).to have_http_status(404)
      expect(response.parsed_body.dig('error', 'code')).to eq('ENDPOINT_DISABLED')
    end

    context 'with a non-local request' do
      def sign_in_from(headers)
        post '/api/signin-flow', params: { username: email, password: password }, headers: headers, as: :json
      end

      it 'rejects cross-origin, missing, configured-subdomain, and plain HTTP allowlisted origins' do
        sign_in_from('HTTP_ORIGIN' => 'https://attacker.example', 'REMOTE_ADDR' => '203.0.113.10')

        expect(response).to have_http_status(403)
        expect(response.parsed_body.dig('error', 'code')).to eq('ORIGIN_NOT_ALLOWED')

        sign_in_from('REMOTE_ADDR' => '127.0.0.1')

        expect(response).to have_http_status(403)

        Setting.misskey_compat_signin_flow_allowed_origins = 'https://frontend.example'
        sign_in_from('HTTP_ORIGIN' => 'https://child.frontend.example', 'REMOTE_ADDR' => '203.0.113.10')

        expect(response).to have_http_status(403)

        Setting.misskey_compat_signin_flow_allowed_origins = 'http://frontend.example'
        sign_in_from('HTTP_ORIGIN' => 'http://frontend.example', 'REMOTE_ADDR' => '203.0.113.10')

        expect(response).to have_http_status(403)
      end

      it 'allows a same-origin request and an exact configured HTTPS origin' do
        sign_in_from('HTTP_ORIGIN' => 'https://local.test', 'REMOTE_ADDR' => '203.0.113.10')

        expect(response).to have_http_status(200)

        Setting.misskey_compat_signin_flow_allowed_origins = 'https://frontend.example'
        sign_in_from('HTTP_ORIGIN' => 'https://frontend.example', 'REMOTE_ADDR' => '203.0.113.10')

        expect(response).to have_http_status(200)
      end
    end

    it 'is not advertised in the endpoints list (parity with Misskey)' do
      post '/api/endpoints', params: {}, as: :json

      expect(response.parsed_body).to_not include('signin-flow')
    end

    it 'asks for the password without looking up the email, giving an unknown email the same first step' do
      [email, 'nobody@example.com'].each do |identifier|
        post '/api/signin-flow', params: { username: identifier }, headers: origin_headers, as: :json

        expect(response).to have_http_status(200), identifier
        expect(response.parsed_body).to eq('finished' => false, 'next' => 'password'), identifier
      end
    end

    it 'finishes with a usable access token on a correct password, matching the email case-insensitively' do
      post '/api/signin-flow', params: { username: email, password: password }, headers: origin_headers, as: :json

      expect(response).to have_http_status(200)
      body = response.parsed_body
      expect(body['finished']).to be(true)
      expect(body['id']).to eq(MisskeyCompat::MiId.encode(user.account_id))

      token = Doorkeeper::AccessToken.by_token(body['i'])
      expect(token&.resource_owner_id).to eq(user.id)
      expect(token.scopes.to_s).to eq(MisskeyCompat::MiAuth::TOKEN_SCOPE)
      expect(token.misskey_access_grant.permissions).to match_array(MisskeyCompat::MiAuth::SUPPORTED_PERMISSIONS)
      expect(token.misskey_access_grant.native_user_token?).to be true

      post '/api/signin-flow', params: { username: "  #{email.upcase} ", password: password }, headers: origin_headers, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body['finished']).to be(true)
    end

    it 'rejects a username, an unknown email, a wrong password, and an account without a local password with the INCORRECT_PASSWORD id' do
      [[username, password], ['nobody@example.com', password], [email, 'nope']].each do |identifier, attempt|
        post '/api/signin-flow', params: { username: identifier, password: attempt }, headers: origin_headers, as: :json

        expect(response).to have_http_status(403), identifier
        expect(response.parsed_body.dig('error', 'id')).to eq(Api::MisskeyCompat::SigninController::INCORRECT_PASSWORD_ID), identifier
      end

      user.update_column(:encrypted_password, '')
      post '/api/signin-flow', params: { username: email, password: password }, headers: origin_headers, as: :json

      expect(response).to have_http_status(403)
      expect(response.parsed_body.dig('error', 'id')).to eq(Api::MisskeyCompat::SigninController::INCORRECT_PASSWORD_ID)
    end

    it 'does not reveal a suspended account before the password is verified, then treats it as an unknown user' do
      user.account.suspend!

      post '/api/signin-flow', params: { username: email, password: 'nope' }, headers: origin_headers, as: :json

      expect(response).to have_http_status(403)
      expect(response.parsed_body.dig('error', 'id')).to eq(Api::MisskeyCompat::SigninController::INCORRECT_PASSWORD_ID)

      post '/api/signin-flow', params: { username: email, password: password }, headers: origin_headers, as: :json

      expect(response).to have_http_status(404)
      expect(response.parsed_body.dig('error', 'id')).to eq(Api::MisskeyCompat::SigninController::NO_SUCH_USER_ID)
    end

    context 'with TOTP two-factor enabled' do
      let!(:user) do
        Fabricate(:user, email: email, password: password, otp_required_for_login: true, otp_secret: User.generate_otp_secret, account_attributes: { username: username })
      end

      it 'asks for the password first, does not ask for TOTP after a wrong password, and asks for TOTP after a correct password' do
        post '/api/signin-flow', params: { username: email }, headers: origin_headers, as: :json

        expect(response).to have_http_status(200)
        expect(response.parsed_body).to eq('finished' => false, 'next' => 'password')

        post '/api/signin-flow', params: { username: email, password: 'nope' }, headers: origin_headers, as: :json

        expect(response).to have_http_status(403)
        expect(response.parsed_body.dig('error', 'id')).to eq(Api::MisskeyCompat::SigninController::INCORRECT_PASSWORD_ID)

        post '/api/signin-flow', params: { username: email, password: password }, headers: origin_headers, as: :json

        expect(response).to have_http_status(200)
        expect(response.parsed_body).to eq('finished' => false, 'next' => 'totp')
      end

      it 'finishes when the TOTP token is valid' do
        post '/api/signin-flow', params: { username: email, password: password, token: user.current_otp }, headers: origin_headers, as: :json

        expect(response).to have_http_status(200)
        expect(response.parsed_body['finished']).to be(true)
        expect(Doorkeeper::AccessToken.by_token(response.parsed_body['i'])&.resource_owner_id).to eq(user.id)
      end

      it 'shares the hourly two-factor attempt limit with the web sign-in' do
        redis.set("2fa_auth_attempts:#{user.id}:#{Time.now.utc.hour}", Auth::SessionsController::MAX_2FA_ATTEMPTS_PER_HOUR)

        post '/api/signin-flow', params: { username: email, password: password, token: user.current_otp }, headers: origin_headers, as: :json

        expect(response).to have_http_status(429)
        expect(response.parsed_body['finished']).to be_nil
      end

      it 'rejects an invalid TOTP token with the Misskey INCORRECT_TOTP id and notifies the owner', :inline_jobs do
        emails = capture_emails do
          post '/api/signin-flow', params: { username: email, password: password, token: '000000' }, headers: origin_headers, as: :json
        end

        expect(response).to have_http_status(403)
        expect(response.parsed_body.dig('error', 'id')).to eq(Api::MisskeyCompat::SigninController::INCORRECT_TOKEN_ID)
        expect(emails.size).to eq(1)
        expect(emails.first.to).to eq([email])
      end
    end
  end
end
