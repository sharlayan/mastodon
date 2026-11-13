# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::RequestExtensions do
  let(:proxy) { { proxy: { proxy_address: 'proxy.test', proxy_port: 8128 } } }
  let(:configured_proxy) { proxy }

  around do |example|
    saved = Rails.configuration.x.http_client_proxy
    example.run
  ensure
    Rails.configuration.x.http_client_proxy = saved
  end

  before do
    Rails.configuration.x.http_client_proxy = configured_proxy
    Setting.link_preview_direct_hosts = "youtube.com\ngoogle.com"
  end

  def options_for(url, **)
    Request.new(:get, url, **).instance_variable_get(:@options)
  end

  context 'with an outgoing proxy' do
    it 'connects only allowed link preview hosts directly and sends everything else through the proxy' do
      direct = options_for('https://www.youtube.com/watch?v=1', route: :link_preview)
      expect(direct).to include(socket_class: Request::Socket)
      expect(direct).to_not include(:proxy, :route)
      expect(direct[:follow]).to include(:on_redirect)

      expect(options_for('https://example.com/article', route: :link_preview)).to include(socket_class: Request::ProxySocket, proxy: proxy[:proxy])
      expect(options_for('https://notyoutube.com/', route: :link_preview)).to include(proxy: proxy[:proxy])
      expect(options_for('https://www.youtube.com/watch?v=1')).to include(proxy: proxy[:proxy])
      expect(options_for('https://www.youtube.com/watch?v=1', route: :media)).to include(proxy: proxy[:proxy])
    end

    it 'follows redirects between allowed hosts directly and retries through the proxy when a redirect leaves them' do
      allow(Request).to receive(:new).and_call_original
      stub_request(:get, 'https://youtube.com/a').to_return(status: 302, headers: { 'Location' => 'https://www.youtube.com/a' })
      stub_request(:get, 'https://www.youtube.com/a').to_return(status: 200, body: 'direct')
      stub_request(:get, 'https://google.com/url').to_return(status: 302, headers: { 'Location' => 'https://tracker.example/' })
      stub_request(:get, 'https://tracker.example/').to_return(status: 200, body: 'proxied')

      direct_body = Request.new(:get, 'https://youtube.com/a', route: :link_preview).perform { |res| res.body.to_s }
      proxied_body = Request.new(:get, 'https://google.com/url', route: :link_preview).add_headers('Accept' => 'text/html').perform { |res| res.body.to_s }

      expect(direct_body).to eq 'direct'
      expect(proxied_body).to eq 'proxied'
      expect(Request).to have_received(:new).with(:get, 'https://google.com/url').once
      expect(Request).to_not have_received(:new).with(:get, 'https://youtube.com/a')
      expect(a_request(:get, 'https://google.com/url').with(headers: { 'Accept' => 'text/html' })).to have_been_made.twice
      expect(a_request(:get, 'https://tracker.example/')).to have_been_made.once
    end

    it 'sends link card and oEmbed fetches on the link preview route' do
      allow(Request).to receive(:new).and_call_original
      stub_request(:get, 'https://example.com/article').to_return(
        status: 200,
        headers: { 'Content-Type' => 'text/html' },
        body: '<html><head><link rel="alternate" type="application/json+oembed" href="https://example.com/oembed?url=article"></head></html>'
      )
      stub_request(:get, 'https://example.com/oembed?url=article').to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: '{}')

      FetchOEmbedService.new.call('https://example.com/article')
      FetchLinkCardService.new.call(Fabricate(:status, text: 'https://example.com/article'))

      expect(Request).to have_received(:new).with(:get, 'https://example.com/article', route: :link_preview).at_least(:twice)
      expect(Request).to have_received(:new).with(:get, 'https://example.com/oembed?url=article', route: :link_preview).at_least(:once)
    end
  end

  context 'without an outgoing proxy' do
    let(:configured_proxy) { {} }

    it 'leaves link preview requests and their redirects unchanged' do
      options = options_for('https://www.youtube.com/watch?v=1', route: :link_preview)

      expect(options).to include(socket_class: Request::Socket)
      expect(options[:follow]).to_not include(:on_redirect)
    end
  end
end
