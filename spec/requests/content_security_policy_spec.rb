# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Content-Security-Policy' do
  before { allow(SecureRandom).to receive(:base64).with(16).and_return('ZbA+JmE7+bK8F5qvADZHuQ==') }

  it 'sets the expected CSP headers' do
    get '/'

    expect(response_csp_headers)
      .to match_array(expected_csp_headers)
  end

  it 'allows the account switch endpoint as a form target' do
    get '/'

    expect(response_csp_headers)
      .to include("form-action #{local_domain}/auth/switch_account")
  end

  context 'with single sign-on configured' do
    before { allow_any_instance_of(ContentSecurityPolicy).to receive(:sso_host).and_return('https://sso.example.com') } # rubocop:disable RSpec/AnyInstance

    it 'keeps the sign-in targets alongside the account switch endpoint' do
      get '/'

      expect(response_csp_headers)
        .to include("form-action https://sso.example.com #{local_domain}/auth/auth/ #{local_domain}/auth/switch_account")
    end
  end

  def response_csp_headers
    response
      .headers['Content-Security-Policy']
      .split(';')
      .map(&:strip)
  end

  def expected_csp_headers
    <<~CSP.split("\n").map(&:strip)
      base-uri 'none'
      child-src 'self' blob: #{local_domain}
      connect-src 'self' data: blob: #{local_domain} #{Rails.configuration.x.streaming_api_base_url}
      default-src 'none'
      font-src 'self' #{local_domain}
      form-action #{local_domain}/auth/switch_account
      frame-ancestors 'none'
      frame-src 'self' https:
      img-src 'self' data: blob: #{local_domain}
      manifest-src 'self' #{local_domain}
      media-src 'self' data: #{local_domain}
      script-src 'self' #{local_domain} 'wasm-unsafe-eval' 'sha256-OgOg5CGI7D4Syg38sNIknJKO+3DCTdpfY1ciC+Bklaw='
      style-src 'self' #{local_domain} 'nonce-ZbA+JmE7+bK8F5qvADZHuQ=='
      worker-src 'self' blob: #{local_domain}
    CSP
  end

  def local_domain
    root_url(host: Rails.configuration.x.local_domain).chop
  end
end
