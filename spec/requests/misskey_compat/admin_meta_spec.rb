# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat admin meta and captcha' do
  let(:role) { Fabricate(:user_role, permissions: UserRole::FLAGS[:manage_settings]) }
  let(:user) { Fabricate(:user, role: role) }
  let!(:token) { MisskeyCompat::MiAuth.issue_native_token(user).token }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  def api(path, **params)
    post "/api/admin/#{path}", params: { i: token }.merge(params), as: :json
    response.parsed_body
  end

  it 'reads Mastodon-backed admin meta without exposing secrets' do
    DomainBlock.create!(domain: 'blocked.example', severity: :suspend)
    DomainBlock.create!(domain: 'quiet.example', severity: :silence, reject_media: true)
    EmailDomainBlock.create!(domain: 'spam.example')

    meta = api('meta')
    expect(meta).to include(name: Setting.site_title, blockedHosts: %w(blocked.example), silencedHosts: %w(quiet.example), mediaSilencedHosts: %w(quiet.example))
    expect(meta).to include(bannedEmailDomains: %w(spam.example), hcaptchaSecretKey: nil, smtpPass: nil, objectStorageSecretKey: nil, proxyAccountId: nil, policies: be_a(Hash))
  end

  it 'maps update-meta fields to Mastodon settings and ignores unrelated keys' do
    Setting.registrations_mode = 'approved'

    api('update-meta', name: 'Renamed', description: 'Short', themeColor: '#123456', disableRegistration: false, notesPerOneAd: 5, smtpHost: 'mail.example', cacheRemoteFiles: false)
    expect(response).to have_http_status(204)
    expect([Setting.site_title, Setting.site_short_description, Setting.theme_color, Setting.registrations_mode]).to eq(%w(Renamed Short #123456 approved))
    expect(Setting.misskey_compat_notes_per_one_ad).to eq(5)

    api('update-meta', disableRegistration: true)
    expect(Setting.registrations_mode).to eq('none')

    api('update-meta', themeColor: 'red')
    expect(response).to have_http_status(400)

    post '/api/meta', as: :json
    expect(response.parsed_body).to include(name: 'Renamed', notesPerOneAd: 5)
  end

  it 'reports env-configured hCaptcha and rejects providers Mastodon cannot use' do
    allow(Rails.configuration.x.captcha).to receive_messages(site_key: 'site-key', secret_key: 'secret-key')

    expect(api('captcha/current')).to include(provider: 'none', hcaptcha: { siteKey: 'site-key', secretKey: nil })

    api('captcha/save', provider: 'hcaptcha', sitekey: 'site-key', secret: 'secret-key')
    expect(response).to have_http_status(204)
    expect(api('captcha/current')[:provider]).to eq('hcaptcha')

    api('captcha/save', provider: 'hcaptcha', sitekey: 'other')
    expect(response.parsed_body.dig(:error, :code)).to eq('INVALID_PARAMETERS')

    api('captcha/save', provider: 'turnstile')
    expect(response.parsed_body.dig(:error, :code)).to eq('INVALID_PROVIDER')

    api('captcha/save', provider: 'none')
    expect(Setting.captcha_enabled).to be(false)
  end

  it 'requires the settings permission and keeps update-proxy-account unsupported' do
    api('update-proxy-account', description: 'x')
    expect(response).to have_http_status(501)

    user.update!(role: Fabricate(:user_role, permissions: UserRole::FLAGS[:manage_users]))
    api('meta')
    expect(response.parsed_body.dig(:error, :id)).to eq('c3d38592-54c0-429d-be96-5636b0431a61')
  end
end
