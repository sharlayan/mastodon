# frozen_string_literal: true

require 'rails_helper'
require 'webauthn/fake_client'

RSpec.describe 'Misskey-compat two-factor endpoints' do
  let(:user)    { Fabricate(:user, password: 'correct horse') }
  let(:account) { user.account }
  let(:token)   { MisskeyCompat::MiAuth.issue_native_token(user).token }
  let(:domain)  { "#{Rails.configuration.x.use_https ? 'https' : 'http'}://#{Rails.configuration.x.web_domain}" }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  def call(endpoint, **params)
    post "/api/i/2fa/#{endpoint}", params: { i: token }.merge(params), as: :json
    response.parsed_body
  end

  def me(access_token = token)
    post '/api/i', params: { i: access_token }, as: :json
    response.parsed_body
  end

  def enable_otp!
    user.update!(otp_required_for_login: true, otp_secret: User.generate_otp_secret)
    user.generate_otp_backup_codes!.tap { user.save! }
  end

  describe 'TOTP' do
    it 'rejects app tokens, wrong passwords and unstarted confirmation' do
      post '/api/i/2fa/register', params: { i: MisskeyCompat::MiAuth.issue_token(user, permission: 'write:account').token, password: 'correct horse' }, as: :json
      expect(response).to have_http_status(403)

      call('register', password: 'wrong')
      expect(response).to have_http_status(400)
      expect(response.parsed_body[:error]).to include(code: 'INCORRECT_PASSWORD', id: '78d6c839-20c9-4c66-b90a-fc0542168b48')

      call('done', token: '000000')
      expect(response).to have_http_status(500)
      expect(response.parsed_body[:error]).to include(code: 'INTERNAL_ERROR')
    end

    it 'registers and confirms a secret and returns the backup codes' do
      registration = call('register', password: 'correct horse')
      expect(registration).to include(label: account.username, issuer: Rails.configuration.x.local_domain)
      expect(registration[:qr]).to start_with('data:image/png;base64,')
      expect(registration[:url]).to start_with('otpauth://totp/').and include(registration[:secret])

      call('done', token: '000000')
      expect(response).to have_http_status(500)
      expect(user.reload.otp_enabled?).to be false

      result = call('done', token: ROTP::TOTP.new(registration[:secret]).at(Time.now.utc))
      expect(result[:backupCodes].size).to eq(User.otp_number_of_backup_codes)
      expect(user.reload).to have_attributes(otp_required_for_login: true, otp_secret: registration[:secret])
      expect(me).to include(twoFactorEnabled: true, usePasswordLessLogin: false, securityKeys: false, twoFactorBackupCodesStock: 'full', securityKeysList: [])
    end

    it 'requires the second factor to unregister and accepts a backup code' do
      backup_codes = enable_otp!

      call('unregister', password: 'correct horse')
      expect(response).to have_http_status(500)
      expect(response.parsed_body.dig(:error, :info, :e, :message)).to eq('authentication failed')

      call('unregister', password: 'correct horse', token: backup_codes.first)
      expect(response).to have_http_status(204)
      expect(user.reload).to have_attributes(otp_required_for_login: false, otp_secret: nil)
    end
  end

  describe 'security keys' do
    let(:other) { Fabricate(:webauthn_credential, user_id: Fabricate(:user).id, nickname: 'Other') }

    it 'requires TOTP before registering a key and registers one through the WebAuthn ceremony' do
      call('register-key', password: 'correct horse')
      expect(response).to have_http_status(400)
      expect(response.parsed_body[:error]).to include(code: 'TWO_FACTOR_NOT_ENABLED', id: 'bf32b864-449b-47b8-974e-f9a5468546f1')

      backup_codes = enable_otp!
      options = call('register-key', password: 'correct horse', token: backup_codes[0])
      expect(options).to include(:challenge, :rp, :user, :pubKeyCredParams)

      credential = WebAuthn::FakeClient.new(domain).create(challenge: options[:challenge])
      created = call('key-done', password: 'correct horse', token: backup_codes[1], name: 'USB Key', credential: credential)
      expect(created).to eq({ 'id' => credential['id'], 'name' => 'USB Key' })

      call('key-done', password: 'correct horse', token: backup_codes[2], name: 'Again', credential: credential)
      expect(response).to have_http_status(500)
      expect(me).to include(securityKeys: true, securityKeysList: [include(id: credential['id'], name: 'USB Key')])
      expect(me(MisskeyCompat::MiAuth.issue_token(user, permission: 'read:account').token)).to include(securityKeys: true).and(satisfy { |body| !body.key?(:securityKeysList) })
    end

    it 'renames only the caller keys and removes them with the password' do
      backup_codes = enable_otp!
      credential = Fabricate(:webauthn_credential, user_id: user.id, nickname: 'USB Key')

      call('update-key', credentialId: credential.external_id, name: 'x' * 31)
      expect(response).to have_http_status(400)

      call('update-key', credentialId: 'missing', name: 'Renamed')
      expect(response.parsed_body.dig(:error, :code)).to eq('NO_SUCH_KEY')

      call('update-key', credentialId: other.external_id, name: 'Mine')
      expect(response).to have_http_status(403)

      expect(call('update-key', credentialId: credential.external_id, name: 'Renamed')).to eq({})
      expect(credential.reload.nickname).to eq('Renamed')

      expect(call('remove-key', password: 'correct horse', token: backup_codes[0], credentialId: credential.external_id)).to eq({})
      expect(user.webauthn_credentials.reload).to be_empty
      expect(other.reload.nickname).to eq('Other')
    end
  end

  it 'keeps password-less sign-in unsupported' do
    call('password-less', value: true)

    expect(response).to have_http_status(501)
  end
end
