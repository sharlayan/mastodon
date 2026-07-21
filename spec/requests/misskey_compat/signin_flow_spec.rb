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
  let(:password) { 'wonderland-123' }
  let(:origin_headers) { { 'HTTP_ORIGIN' => 'https://local.test' } }
  let!(:user) { Fabricate(:user, password: password, account_attributes: { username: username }) }

  describe 'POST /api/signin-flow' do
    context 'when the compat gate is off' do
      before { Setting.misskey_compat_enabled = false }

      it 'is not routed as an available endpoint' do
        post '/api/signin-flow', params: { username: username, password: password }, headers: origin_headers, as: :json

        expect(response).to have_http_status(404)
        expect(response.parsed_body.dig('error', 'code')).to eq('ENDPOINT_DISABLED')
      end
    end

    context 'when the dedicated signin-flow gate is off' do
      before { Setting.misskey_compat_signin_flow_enabled = false }

      it 'remains disabled even when Misskey compatibility is enabled' do
        post '/api/signin-flow', params: { username: username, password: password }, headers: origin_headers, as: :json

        expect(response).to have_http_status(404)
        expect(response.parsed_body.dig('error', 'code')).to eq('ENDPOINT_DISABLED')
      end
    end

    context 'with a non-local request' do
      it 'rejects a cross-origin request' do
        post '/api/signin-flow',
             params: { username: username, password: password },
             headers: { 'HTTP_ORIGIN' => 'https://attacker.example', 'REMOTE_ADDR' => '203.0.113.10' },
             as: :json

        expect(response).to have_http_status(403)
        expect(response.parsed_body.dig('error', 'code')).to eq('ORIGIN_NOT_ALLOWED')
      end

      it 'allows a same-origin request' do
        post '/api/signin-flow',
             params: { username: username, password: password },
             headers: { 'HTTP_ORIGIN' => 'https://local.test', 'REMOTE_ADDR' => '203.0.113.10' },
             as: :json

        expect(response).to have_http_status(200)
      end

      it 'rejects a request without an Origin header' do
        post '/api/signin-flow',
             params: { username: username, password: password },
             headers: { 'REMOTE_ADDR' => '127.0.0.1' },
             as: :json

        expect(response).to have_http_status(403)
      end

      it 'allows an exact configured HTTPS origin' do
        Setting.misskey_compat_signin_flow_allowed_origins = 'https://frontend.example'

        post '/api/signin-flow',
             params: { username: username, password: password },
             headers: { 'HTTP_ORIGIN' => 'https://frontend.example', 'REMOTE_ADDR' => '203.0.113.10' },
             as: :json

        expect(response).to have_http_status(200)
      end

      it 'does not implicitly allow a subdomain of a configured origin' do
        Setting.misskey_compat_signin_flow_allowed_origins = 'https://frontend.example'

        post '/api/signin-flow',
             params: { username: username, password: password },
             headers: { 'HTTP_ORIGIN' => 'https://child.frontend.example', 'REMOTE_ADDR' => '203.0.113.10' },
             as: :json

        expect(response).to have_http_status(403)
      end

      it 'does not accept an HTTP origin from the additional allowlist' do
        Setting.misskey_compat_signin_flow_allowed_origins = 'http://frontend.example'

        post '/api/signin-flow',
             params: { username: username, password: password },
             headers: { 'HTTP_ORIGIN' => 'http://frontend.example', 'REMOTE_ADDR' => '203.0.113.10' },
             as: :json

        expect(response).to have_http_status(403)
      end
    end

    it 'is not advertised in the endpoints list (parity with Misskey)' do
      post '/api/endpoints', params: {}, as: :json

      expect(response.parsed_body).to_not include('signin-flow')
    end

    it 'asks for the password first when none is supplied and 2FA is off' do
      post '/api/signin-flow', params: { username: username }, headers: origin_headers, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to eq('finished' => false, 'next' => 'captcha')
    end

    it 'finishes with a usable access token on a correct password' do
      post '/api/signin-flow', params: { username: username, password: password }, headers: origin_headers, as: :json

      expect(response).to have_http_status(200)
      body = response.parsed_body
      expect(body['finished']).to be(true)
      expect(body['id']).to eq(MisskeyCompat::MiId.encode(user.account_id))

      token = Doorkeeper::AccessToken.by_token(body['i'])
      expect(token&.resource_owner_id).to eq(user.id)
      expect(token.scopes.to_s).to eq(MisskeyCompat::MiAuth::TOKEN_SCOPE)
      expect(token.misskey_access_grant.permissions).to match_array(MisskeyCompat::MiAuth::SUPPORTED_PERMISSIONS)
    end

    it 'is case-insensitive on the username and tolerates a leading @' do
      post '/api/signin-flow', params: { username: "@#{username.upcase}", password: password }, headers: origin_headers, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body['finished']).to be(true)
    end

    it 'rejects an unknown user with the Misskey NO_SUCH_USER id' do
      post '/api/signin-flow', params: { username: 'nobody', password: password }, headers: origin_headers, as: :json

      expect(response).to have_http_status(404)
      expect(response.parsed_body.dig('error', 'id')).to eq(Api::MisskeyCompat::SigninController::NO_SUCH_USER_ID)
    end

    it 'rejects a wrong password with the Misskey INCORRECT_PASSWORD id' do
      post '/api/signin-flow', params: { username: username, password: 'nope' }, headers: origin_headers, as: :json

      expect(response).to have_http_status(403)
      expect(response.parsed_body.dig('error', 'id')).to eq(Api::MisskeyCompat::SigninController::INCORRECT_PASSWORD_ID)
    end

    it 'rejects a suspended account' do
      user.account.suspend!

      post '/api/signin-flow', params: { username: username, password: password }, headers: origin_headers, as: :json

      expect(response).to have_http_status(403)
      expect(response.parsed_body.dig('error', 'id')).to eq(Api::MisskeyCompat::SigninController::SUSPENDED_ID)
    end

    context 'with TOTP two-factor enabled' do
      let!(:user) do
        Fabricate(:user, password: password, otp_required_for_login: true, otp_secret: User.generate_otp_secret, account_attributes: { username: username })
      end

      it 'asks for the TOTP step after a correct password' do
        post '/api/signin-flow', params: { username: username, password: password }, headers: origin_headers, as: :json

        expect(response).to have_http_status(200)
        expect(response.parsed_body).to eq('finished' => false, 'next' => 'totp')
      end

      it 'finishes when the TOTP token is valid' do
        post '/api/signin-flow', params: { username: username, password: password, token: user.current_otp }, headers: origin_headers, as: :json

        expect(response).to have_http_status(200)
        expect(response.parsed_body['finished']).to be(true)
        expect(Doorkeeper::AccessToken.by_token(response.parsed_body['i'])&.resource_owner_id).to eq(user.id)
      end

      it 'rejects an invalid TOTP token with the Misskey INCORRECT_TOTP id' do
        post '/api/signin-flow', params: { username: username, password: password, token: '000000' }, headers: origin_headers, as: :json

        expect(response).to have_http_status(403)
        expect(response.parsed_body.dig('error', 'id')).to eq(Api::MisskeyCompat::SigninController::INCORRECT_TOKEN_ID)
      end
    end
  end
end
