# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FetchInstanceThemeColorService do
  subject { described_class.new }

  let(:domain) { 'remote.example.com' }

  before do
    # This spec exercises the real remote fetch, so opt out of the test-env
    # network guard that other specs rely on.
    described_class.allow_remote_fetch_in_test = true

    # Default stubs for all external requests
    stub_request(:get, "https://#{domain}").to_return(status: 200, body: default_html, headers: { 'Content-Type' => 'text/html' })
    stub_request(:get, "https://#{domain}/nodeinfo/2.1").to_return(status: 404)
    stub_request(:post, "https://#{domain}/api/meta").to_return(status: 404)
    stub_request(:get, "https://#{domain}/.well-known/nodeinfo").to_return(status: 404)
    stub_request(:get, "https://#{domain}/manifest.json").to_return(status: 404)
    stub_request(:get, "https://#{domain}/api/v1/instance").to_return(status: 404)
    stub_request(:get, "https://#{domain}/api/v2/instance").to_return(status: 404)
    stub_request(:get, "https://#{domain}/favicon.ico").to_return(status: 200, body: 'fake-ico-data')
    stub_request(:get, "https://#{domain}/custom-favicon.png").to_return(status: 200, body: 'png-data')

    # Ensure favicon storage directory exists
    storage_path = Rails.public_path.join('system', 'instance_favicons')
    FileUtils.mkdir_p(storage_path)
  end

  after do
    described_class.allow_remote_fetch_in_test = false

    # Clean up favicon files
    storage_path = Rails.public_path.join('system', 'instance_favicons')
    FileUtils.rm_rf(storage_path)
  end

  def default_html
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <meta name="theme-color" content="#FF5500">
        <link rel="icon" href="/custom-favicon.png">
        <meta property="og:site_name" content="Remote Instance">
        <title>Remote Instance Title</title>
      </head>
      <body></body>
      </html>
    HTML
  end

  describe '#call' do
    it 'creates and returns instance metadata' do
      result = subject.call(domain)
      expect(result).to be_a(InstanceMetadata)
      expect(result.domain).to eq(domain)
    end

    it 'updates metadata timestamps' do
      result = subject.call(domain)
      expect(result.theme_color_updated_at).to be_within(5.seconds).of(Time.now.utc)
      expect(result.metadata_updated_at).to be_within(5.seconds).of(Time.now.utc)
    end

    it 'fetches homepage HTML only once' do
      stub_request(:get, "https://#{domain}/favicon.ico").to_return(status: 404)
      stub_request(:get, "https://#{domain}/custom-favicon.png").to_return(status: 200, body: 'png-data')

      subject.call(domain)

      expect(WebMock).to have_requested(:get, "https://#{domain}").once
    end

    it 'fetches nodeinfo only once when used by both software and name detection' do
      nodeinfo_well_known = {
        links: [{ rel: 'http://nodeinfo.diaspora.software/ns/schema/2.0', href: "https://#{domain}/nodeinfo/2.0" }],
      }.to_json

      nodeinfo_response = {
        software: { name: 'mastodon', version: '4.0.0' },
        metadata: { nodeName: 'Mastodon Instance' },
      }.to_json

      stub_request(:get, "https://#{domain}/.well-known/nodeinfo").to_return(status: 200, body: nodeinfo_well_known, headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, "https://#{domain}/nodeinfo/2.0").to_return(status: 200, body: nodeinfo_response, headers: { 'Content-Type' => 'application/json' })

      subject.call(domain)

      expect(WebMock).to have_requested(:get, "https://#{domain}/.well-known/nodeinfo").once
      expect(WebMock).to have_requested(:get, "https://#{domain}/nodeinfo/2.0").once
    end
  end

  describe 'theme color extraction' do
    it 'extracts theme-color meta tag' do
      result = subject.call(domain)
      expect(result.theme_color).to eq('#FF5500')
    end

    it 'extracts msapplication-TileColor as fallback' do
      html = <<~HTML
        <html><head>
          <meta name="msapplication-TileColor" content="#AA00BB">
        </head><body></body></html>
      HTML
      stub_request(:get, "https://#{domain}").to_return(status: 200, body: html)

      result = subject.call(domain)
      expect(result.theme_color).to eq('#AA00BB')
    end

    it 'falls back to default theme color when no color meta tags' do
      html = '<html><head></head><body></body></html>'
      stub_request(:get, "https://#{domain}").to_return(status: 200, body: html)

      result = subject.call(domain)
      expect(result.theme_color).to eq(result.default_theme_color)
    end

    it 'normalizes 3-digit hex to 6-digit' do
      html = '<html><head><meta name="theme-color" content="#F0A"></head><body></body></html>'
      stub_request(:get, "https://#{domain}").to_return(status: 200, body: html)

      result = subject.call(domain)
      expect(result.theme_color).to eq('#FF00AA')
    end

    it 'rejects invalid color values and uses default' do
      html = '<html><head><meta name="theme-color" content="not-a-color"></head><body></body></html>'
      stub_request(:get, "https://#{domain}").to_return(status: 200, body: html)

      result = subject.call(domain)
      expect(result.theme_color).to eq(result.default_theme_color)
    end
  end

  describe 'favicon detection' do
    # The service stores favicons under a SHA1 digest of the domain and derives
    # the file extension from the response Content-Type.
    let(:favicon_dir) { '/system/instance_favicons' }
    let(:domain_digest) { Digest::SHA1.hexdigest(domain) }

    before do
      stub_request(:get, "https://#{domain}/custom-favicon.png").to_return(status: 200, body: 'png-data', headers: { 'Content-Type' => 'image/png' })
    end

    it 'extracts favicon from link[rel="icon"] tag' do
      result = subject.call(domain)
      expect(result.favicon_url).to eq("#{favicon_dir}/#{domain_digest}.png")
    end

    it 'falls back to /favicon.ico when no link tag' do
      html = '<html><head></head><body></body></html>'
      stub_request(:get, "https://#{domain}").to_return(status: 200, body: html)
      stub_request(:get, "https://#{domain}/favicon.ico").to_return(status: 200, body: 'fake-ico-data', headers: { 'Content-Type' => 'image/x-icon' })

      result = subject.call(domain)
      expect(result.favicon_url).to eq("#{favicon_dir}/#{domain_digest}.ico")
    end

    it 'handles protocol-relative favicon URLs' do
      html = '<html><head><link rel="icon" href="//cdn.example.com/favicon.png"></head><body></body></html>'
      stub_request(:get, "https://#{domain}").to_return(status: 200, body: html)
      stub_request(:get, 'https://cdn.example.com/favicon.png').to_return(status: 200, body: 'png-data', headers: { 'Content-Type' => 'image/png' })

      result = subject.call(domain)
      expect(result.favicon_url).to eq("#{favicon_dir}/#{domain_digest}.png")
    end

    it 'handles absolute favicon URLs' do
      html = '<html><head><link rel="icon" href="https://cdn.example.com/icon.png"></head><body></body></html>'
      stub_request(:get, "https://#{domain}").to_return(status: 200, body: html)
      stub_request(:get, 'https://cdn.example.com/icon.png').to_return(status: 200, body: 'png-data', headers: { 'Content-Type' => 'image/png' })

      result = subject.call(domain)
      expect(result.favicon_url).to eq("#{favicon_dir}/#{domain_digest}.png")
    end

    it 'uses favicon_from_api when set by Misskey API' do
      misskey_meta_response = { name: 'Misskey Instance', iconUrl: 'https://cdn.misskey.example/icon.png' }.to_json
      stub_request(:post, "https://#{domain}/api/meta").to_return(status: 200, body: misskey_meta_response, headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, 'https://cdn.misskey.example/icon.png').to_return(status: 200, body: 'misskey-icon', headers: { 'Content-Type' => 'image/png' })

      result = subject.call(domain)
      expect(result.favicon_url).to eq("#{favicon_dir}/#{domain_digest}.png")
    end

    it 'captures the Misskey API iconUrl even when the instance name is present' do
      misskey_meta_response = { name: 'Misskey Instance', iconUrl: 'https://cdn.misskey.example/icon.png' }.to_json
      stub_request(:post, "https://#{domain}/api/meta").to_return(status: 200, body: misskey_meta_response, headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, 'https://cdn.misskey.example/icon.png').to_return(status: 200, body: 'misskey-icon', headers: { 'Content-Type' => 'image/png' })

      subject.call(domain)

      expect(WebMock).to have_requested(:get, 'https://cdn.misskey.example/icon.png')
    end

    it 'prefers the web app manifest icon over the homepage link tag' do
      manifest = { icons: [{ src: '/manifest-icon.png', sizes: '512x512', type: 'image/png' }] }.to_json
      stub_request(:get, "https://#{domain}/manifest.json").to_return(status: 200, body: manifest, headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, "https://#{domain}/manifest-icon.png").to_return(status: 200, body: 'manifest-png', headers: { 'Content-Type' => 'image/png' })

      subject.call(domain)

      expect(WebMock).to have_requested(:get, "https://#{domain}/manifest-icon.png")
      expect(WebMock).to_not have_requested(:get, "https://#{domain}/custom-favicon.png")
    end

    it 'selects the largest icon from the manifest' do
      manifest = { icons: [
        { src: '/small.png', sizes: '36x36', type: 'image/png' },
        { src: '/large.png', sizes: '512x512', type: 'image/png' },
        { src: '/medium.png', sizes: '192x192', type: 'image/png' },
      ] }.to_json
      stub_request(:get, "https://#{domain}/manifest.json").to_return(status: 200, body: manifest, headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, "https://#{domain}/large.png").to_return(status: 200, body: 'large-png', headers: { 'Content-Type' => 'image/png' })

      subject.call(domain)

      expect(WebMock).to have_requested(:get, "https://#{domain}/large.png")
    end

    it 'ignores data URI icons in the manifest' do
      manifest = { icons: [{ src: 'data:image/png;base64,AAAA', sizes: '512x512' }] }.to_json
      stub_request(:get, "https://#{domain}/manifest.json").to_return(status: 200, body: manifest, headers: { 'Content-Type' => 'application/json' })

      result = subject.call(domain)

      expect(result.favicon_url).to eq("#{favicon_dir}/#{domain_digest}.png")
      expect(WebMock).to have_requested(:get, "https://#{domain}/custom-favicon.png")
    end
  end

  describe 'software detection' do
    it 'identifies Misskey from nodeinfo/2.1 POST response' do
      misskey_response = { repositoryUrl: 'https://github.com/misskey-dev/misskey', version: '2024.0.0' }.to_json
      stub_request(:get, "https://#{domain}/nodeinfo/2.1").to_return(status: 200, body: misskey_response, headers: { 'Content-Type' => 'application/json' })

      result = subject.call(domain)
      expect(result.software).to eq('misskey')
    end

    it 'identifies Sharkey from repository URL' do
      sharkey_response = { repositoryUrl: 'https://activitypub.software/TransFem-org/Sharkey', version: '2024.0.0' }.to_json
      stub_request(:get, "https://#{domain}/nodeinfo/2.1").to_return(status: 200, body: sharkey_response, headers: { 'Content-Type' => 'application/json' })

      result = subject.call(domain)
      expect(result.software).to eq('sharkey')
    end

    it 'identifies Firefish from version string' do
      firefish_response = { repositoryUrl: 'https://example.com/repo', version: '1.0.0-firefish' }.to_json
      stub_request(:get, "https://#{domain}/nodeinfo/2.1").to_return(status: 200, body: firefish_response, headers: { 'Content-Type' => 'application/json' })

      result = subject.call(domain)
      expect(result.software).to eq('firefish')
    end

    it 'falls back to nodeinfo for non-Misskey software' do
      nodeinfo_well_known = {
        links: [{ rel: 'http://nodeinfo.diaspora.software/ns/schema/2.0', href: "https://#{domain}/nodeinfo/2.0" }],
      }.to_json
      nodeinfo_response = { software: { name: 'pleroma', version: '2.6.0' }, metadata: {} }.to_json

      stub_request(:get, "https://#{domain}/.well-known/nodeinfo").to_return(status: 200, body: nodeinfo_well_known, headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, "https://#{domain}/nodeinfo/2.0").to_return(status: 200, body: nodeinfo_response, headers: { 'Content-Type' => 'application/json' })

      result = subject.call(domain)
      expect(result.software).to eq('pleroma')
      expect(result.version).to eq('2.6.0')
    end

    it 'returns nil when all methods fail' do
      result = subject.call(domain)
      expect(result.software).to be_nil
    end
  end

  describe 'instance name resolution' do
    it 'prefers Misskey API name' do
      misskey_meta_response = { name: 'Misskey Hub' }.to_json
      stub_request(:post, "https://#{domain}/api/meta").to_return(status: 200, body: misskey_meta_response, headers: { 'Content-Type' => 'application/json' })

      result = subject.call(domain)
      expect(result.instance_name).to eq('Misskey Hub')
    end

    it 'falls back to nodeinfo nodeName' do
      nodeinfo_well_known = {
        links: [{ rel: 'http://nodeinfo.diaspora.software/ns/schema/2.0', href: "https://#{domain}/nodeinfo/2.0" }],
      }.to_json
      nodeinfo_response = { software: { name: 'mastodon', version: '4.0.0' }, metadata: { nodeName: 'Node Instance' } }.to_json

      stub_request(:get, "https://#{domain}/.well-known/nodeinfo").to_return(status: 200, body: nodeinfo_well_known, headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, "https://#{domain}/nodeinfo/2.0").to_return(status: 200, body: nodeinfo_response, headers: { 'Content-Type' => 'application/json' })

      result = subject.call(domain)
      expect(result.instance_name).to eq('Node Instance')
    end

    it 'falls back to HTML og:site_name' do
      result = subject.call(domain)
      expect(result.instance_name).to eq('Remote Instance')
    end

    it 'falls back to Mastodon API v1 title' do
      html = '<html><head></head><body></body></html>'
      stub_request(:get, "https://#{domain}").to_return(status: 200, body: html)

      api_response = { title: 'API Instance Name' }.to_json
      stub_request(:get, "https://#{domain}/api/v1/instance").to_return(status: 200, body: api_response, headers: { 'Content-Type' => 'application/json' })

      result = subject.call(domain)
      expect(result.instance_name).to eq('API Instance Name')
    end

    it 'falls back to Mastodon API v2 title' do
      html = '<html><head></head><body></body></html>'
      stub_request(:get, "https://#{domain}").to_return(status: 200, body: html)

      stub_request(:get, "https://#{domain}/api/v1/instance").to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
      api_v2_response = { title: 'API v2 Instance' }.to_json
      stub_request(:get, "https://#{domain}/api/v2/instance").to_return(status: 200, body: api_v2_response, headers: { 'Content-Type' => 'application/json' })

      result = subject.call(domain)
      expect(result.instance_name).to eq('API v2 Instance')
    end

    it 'falls back to domain as last resort' do
      html = '<html><head></head><body></body></html>'
      stub_request(:get, "https://#{domain}").to_return(status: 200, body: html)
      stub_request(:get, "https://#{domain}/api/v1/instance").to_return(status: 200, body: '{}')
      stub_request(:get, "https://#{domain}/api/v2/instance").to_return(status: 200, body: '{}')

      result = subject.call(domain)
      expect(result.instance_name_with_fallback).to eq(domain)
    end
  end

  describe 'error handling' do
    it 'handles HTTP::Error gracefully and still returns metadata with defaults' do
      stub_request(:get, "https://#{domain}").to_raise(HTTP::Error)
      stub_request(:get, "https://#{domain}/nodeinfo/2.1").to_raise(HTTP::Error)
      stub_request(:post, "https://#{domain}/api/meta").to_raise(HTTP::Error)

      result = subject.call(domain)
      expect(result).to be_a(InstanceMetadata)
      expect(result.software).to be_nil
      expect(result.instance_name_with_fallback).to eq(domain)
    end

    it 'handles OpenSSL::SSL::SSLError gracefully' do
      stub_request(:get, "https://#{domain}").to_raise(OpenSSL::SSL::SSLError)
      stub_request(:get, "https://#{domain}/nodeinfo/2.1").to_raise(OpenSSL::SSL::SSLError)
      stub_request(:post, "https://#{domain}/api/meta").to_raise(OpenSSL::SSL::SSLError)

      result = subject.call(domain)
      expect(result).to be_a(InstanceMetadata)
      expect(result.software).to be_nil
    end

    it 'handles SocketError gracefully' do
      stub_request(:get, "https://#{domain}").to_raise(SocketError)
      stub_request(:get, "https://#{domain}/nodeinfo/2.1").to_raise(SocketError)
      stub_request(:post, "https://#{domain}/api/meta").to_raise(SocketError)

      result = subject.call(domain)
      expect(result).to be_a(InstanceMetadata)
      expect(result.software).to be_nil
    end

    it 'updates timestamps even when individual fetches fail' do
      stub_request(:get, "https://#{domain}").to_raise(HTTP::Error)
      stub_request(:get, "https://#{domain}/nodeinfo/2.1").to_raise(HTTP::Error)
      stub_request(:post, "https://#{domain}/api/meta").to_raise(HTTP::Error)

      subject.call(domain)
      metadata = InstanceMetadata.find_by(domain: domain)
      expect(metadata.theme_color_updated_at).to be_within(5.seconds).of(Time.now.utc)
      expect(metadata.metadata_updated_at).to be_within(5.seconds).of(Time.now.utc)
    end
  end

  describe 'favicon download' do
    it 'downloads and saves favicon to local storage' do
      stub_request(:get, "https://#{domain}/custom-favicon.png").to_return(status: 200, body: 'png-data')

      result = subject.call(domain)
      expect(result.favicon_url).to start_with('/system/instance_favicons/')

      file_path = Rails.public_path.join(result.favicon_url.delete_prefix('/'))
      expect(File.exist?(file_path)).to be true
    end

    it 'uses a digest of the domain for the filename' do
      special_domain = 'sub.example.com'
      stub_request(:get, "https://#{special_domain}").to_return(status: 200, body: default_html)
      stub_request(:get, "https://#{special_domain}/nodeinfo/2.1").to_return(status: 404)
      stub_request(:post, "https://#{special_domain}/api/meta").to_return(status: 404)
      stub_request(:get, "https://#{special_domain}/.well-known/nodeinfo").to_return(status: 404)
      stub_request(:get, "https://#{special_domain}/manifest.json").to_return(status: 404)
      stub_request(:get, "https://#{special_domain}/api/v1/instance").to_return(status: 404)
      stub_request(:get, "https://#{special_domain}/api/v2/instance").to_return(status: 404)
      stub_request(:get, "https://#{special_domain}/custom-favicon.png").to_return(status: 200, body: 'png-data', headers: { 'Content-Type' => 'image/png' })

      result = subject.call(special_domain)
      expect(result.favicon_url).to eq("/system/instance_favicons/#{Digest::SHA1.hexdigest(special_domain)}.png")
    end

    it 'falls back to a generated blank favicon when the download fails' do
      stub_request(:get, "https://#{domain}/custom-favicon.png").to_return(status: 500)

      result = subject.call(domain)
      expect(result.favicon_url).to eq("/system/instance_favicons/#{Digest::SHA1.hexdigest(domain)}.png")
    end
  end
end
