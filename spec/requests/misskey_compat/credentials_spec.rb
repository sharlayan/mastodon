# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat password and email endpoints' do
  let(:user)  { Fabricate(:user, email: 'alice@example.com', password: 'correct horse') }
  let(:token) { MisskeyCompat::MiAuth.issue_native_token(user).token }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  describe 'POST /api/i/change-password' do
    it 'requires the native token and current password and keeps Mastodon password rules' do
      user.session_activations.activate(session_id: 'web', user_agent: 'UA', ip: '127.0.0.1')

      post '/api/i/change-password', params: { i: MisskeyCompat::MiAuth.issue_token(user, permission: 'write:account').token, currentPassword: 'correct horse', newPassword: 'battery staple' }, as: :json
      expect(response).to have_http_status(403)

      post '/api/i/change-password', params: { i: token, currentPassword: 'wrong', newPassword: 'battery staple' }, as: :json
      expect(response).to have_http_status(500)
      expect(response.parsed_body.dig(:error, :info, :e, :message)).to eq('incorrect password')

      post '/api/i/change-password', params: { i: token, currentPassword: 'correct horse', newPassword: 'short' }, as: :json
      expect(response).to have_http_status(400)

      post '/api/i/change-password', params: { i: token, currentPassword: 'correct horse', newPassword: 'battery staple' }, as: :json
      expect(response).to have_http_status(204)
      expect(user.reload.valid_password?('battery staple')).to be true
      expect(user.session_activations).to be_empty
    end
  end

  describe 'POST /api/i/update-email' do
    it 'rejects a wrong password, a missing address and an address in use' do
      Fabricate(:user, email: 'taken@example.com')

      post '/api/i/update-email', params: { i: token, password: 'wrong', email: 'new@example.com' }, as: :json
      expect(response.parsed_body[:error]).to include(code: 'INCORRECT_PASSWORD', id: 'e54c1d7e-e7d6-4103-86b6-0a95069b4ad3')

      post '/api/i/update-email', params: { i: token, password: 'correct horse', email: nil }, as: :json
      expect(response.parsed_body[:error]).to include(code: 'EMAIL_REQUIRED')

      post '/api/i/update-email', params: { i: token, password: 'correct horse', email: 'taken@example.com' }, as: :json
      expect(response.parsed_body[:error]).to include(code: 'UNAVAILABLE', id: 'a2defefb-f220-8849-0af6-17f816099323')
      expect(user.reload.email).to eq('alice@example.com')
    end

    it 'starts Devise reconfirmation and completes it through verify-email' do
      post '/api/i/update-email', params: { i: token, password: 'correct horse', email: 'new@example.com' }, as: :json
      expect(response).to have_http_status(200)
      expect(response.parsed_body).to include(email: 'new@example.com', emailVerified: false)
      expect(user.reload).to have_attributes(email: 'alice@example.com', unconfirmed_email: 'new@example.com')

      post '/api/verify-email', params: { code: 'missing' }, as: :json
      expect(response).to have_http_status(404)
      expect(response.parsed_body[:error]).to include(code: 'NO_SUCH_CODE', id: '97c1f576-e4b8-4b8a-a6dc-9cb65e7f6f85')

      post '/api/verify-email', params: { code: user.confirmation_token }, as: :json
      expect(response).to have_http_status(204)
      expect(user.reload).to have_attributes(email: 'new@example.com', unconfirmed_email: nil)
    end
  end

  describe 'password reset' do
    it 'sends Devise reset instructions only for a matching confirmed local account' do
      post '/api/request-reset-password', params: { username: user.account.username, email: 'other@example.com' }, as: :json
      expect(response).to have_http_status(204)
      expect(user.reload.reset_password_token).to be_nil

      post '/api/request-reset-password', params: { username: user.account.username, email: 'Alice@example.com' }, as: :json
      expect(response).to have_http_status(204)
      expect(user.reload.reset_password_token).to be_present

      post '/api/request-reset-password', params: { username: 'nobody', email: 'alice@example.com' }, as: :json
      expect(response).to have_http_status(204)

      post '/api/request-reset-password', params: { username: user.account.username, email: 'alice@example.com' }, as: :json
      expect(response).to have_http_status(429)
    end

    it 'resets the password with the Devise token and revokes existing access' do
      access_token = token
      reset_token = user.send_reset_password_instructions

      post '/api/reset-password', params: { token: 'invalid', password: 'battery staple' }, as: :json
      expect(response).to have_http_status(500)

      post '/api/reset-password', params: { token: reset_token, password: 'short' }, as: :json
      expect(response).to have_http_status(400)

      post '/api/reset-password', params: { token: reset_token, password: 'battery staple' }, as: :json
      expect(response).to have_http_status(204)
      expect(user.reload.valid_password?('battery staple')).to be true
      expect(Doorkeeper::AccessToken.by_token(access_token)).to be_revoked
    end
  end
end
