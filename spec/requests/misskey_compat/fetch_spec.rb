# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat server-side fetch endpoints' do
  let(:user)        { Fabricate(:user) }
  let(:token)       { MisskeyCompat::MiAuth.issue_native_token(user).token }
  let(:app_token)   { MisskeyCompat::MiAuth.issue_token(user, permission: 'read:account').token }

  before { Setting.misskey_compat_enabled = true }

  after do
    Setting.misskey_compat_enabled = false
    Rails.cache.clear
  end

  describe 'fetch-rss' do
    let(:rss) do
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
          <channel>
            <title>Example feed</title>
            <link>https://feed.example/</link>
            <description>About things</description>
            <atom:link href="https://feed.example/rss" rel="self" type="application/rss+xml" />
            <atom:link href="https://feed.example/rss?page=2" rel="next" />
            <image><url>https://feed.example/logo.png</url><title>Logo</title><link>https://feed.example/</link></image>
            <itunes:author>Host</itunes:author>
            <itunes:image href="https://feed.example/cover.png" />
            <itunes:category text="Technology" />
            <itunes:keywords>a,b</itunes:keywords>
            <item>
              <title>First &amp; best</title>
              <link>https://feed.example/1</link>
              <guid isPermaLink="false">post-1</guid>
              <pubDate>Mon, 02 Nov 2026 10:00:00 +0900</pubDate>
              <dc:creator>Alice</dc:creator>
              <description><![CDATA[<p>Hello</p><p>world &amp; you</p>]]></description>
              <category>news</category>
              <category domain="x">tech</category>
              <enclosure url="https://feed.example/1.mp3" length="1234" type="audio/mpeg" />
            </item>
          </channel>
        </rss>
      XML
    end

    it 'parses RSS 2.0 into the rss-parser shape, caches it, and serves anonymous GET requests' do
      stub = stub_request(:get, 'https://feed.example/rss').to_return(status: 200, body: rss, headers: { 'Content-Type' => 'application/rss+xml' })

      get '/api/fetch-rss', params: { url: 'https://feed.example/rss' }

      expect(response).to have_http_status(200)
      expect(response.headers['Cache-Control']).to include('public', 'max-age=180')
      expect(response.parsed_body.deep_symbolize_keys).to eq(
        title: 'Example feed',
        link: 'https://feed.example/',
        description: 'About things',
        feedUrl: 'https://feed.example/rss',
        paginationLinks: { self: 'https://feed.example/rss', next: 'https://feed.example/rss?page=2' },
        image: { url: 'https://feed.example/logo.png', title: 'Logo', link: 'https://feed.example/' },
        itunes: { author: 'Host', image: 'https://feed.example/cover.png', categories: %w(Technology), keywords: %w(a b) },
        items: [{
          title: 'First & best',
          link: 'https://feed.example/1',
          guid: 'post-1',
          pubDate: 'Mon, 02 Nov 2026 10:00:00 +0900',
          isoDate: '2026-11-02T01:00:00.000Z',
          creator: 'Alice',
          content: '<p>Hello</p><p>world &amp; you</p>',
          contentSnippet: "Hello\nworld & you",
          categories: %w(news tech),
          enclosure: { url: 'https://feed.example/1.mp3', length: 1234, type: 'audio/mpeg' },
        }]
      )

      post '/api/fetch-rss', params: { url: 'https://feed.example/rss', i: app_token }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:title]).to eq('Example feed')
      expect(stub).to have_been_requested.once
    end

    it 'parses Atom feeds' do
      atom = <<~XML
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title type="text">Atom feed</title>
          <link href="https://atom.example/" />
          <link rel="self" href="https://atom.example/atom" />
          <entry>
            <title>Entry</title>
            <id>urn:entry:1</id>
            <link rel="alternate" href="https://atom.example/1" />
            <published>2026-11-01T00:00:00Z</published>
            <author><name>Bob</name></author>
            <content type="html">&lt;b&gt;Bold&lt;/b&gt;</content>
            <summary>Short</summary>
          </entry>
        </feed>
      XML
      stub_request(:get, 'https://atom.example/atom').to_return(status: 200, body: atom)

      post '/api/fetch-rss', params: { url: 'https://atom.example/atom' }, as: :json

      expect(response.parsed_body.deep_symbolize_keys).to eq(
        title: 'Atom feed',
        link: 'https://atom.example/',
        feedUrl: 'https://atom.example/atom',
        items: [{ title: 'Entry', link: 'https://atom.example/1', pubDate: '2026-11-01T00:00:00.000Z', isoDate: '2026-11-01T00:00:00.000Z', creator: 'Bob', content: '<b>Bold</b>', contentSnippet: 'Bold', summary: 'Short', guid: 'urn:entry:1' }]
      )
    end

    it 'rejects invalid URLs and reports fetch, size and parse failures as internal errors' do
      post '/api/fetch-rss', params: { url: 'file:///etc/passwd' }, as: :json
      expect(response).to have_http_status(400)

      post '/api/fetch-rss', as: :json
      expect(response.parsed_body.dig(:error, :info, :param)).to eq('#/properties/url')

      stub_request(:get, 'https://private.example/rss').to_raise(Mastodon::PrivateNetworkAddressError.new('private.example'))
      stub_request(:get, 'https://missing.example/rss').to_return(status: 404)
      stub_request(:get, 'https://huge.example/rss').to_return(status: 200, body: 'x' * (Api::MisskeyCompat::FetchController::RSS_SIZE_LIMIT + 1))
      stub_request(:get, 'https://html.example/rss').to_return(status: 200, body: '<html><body>nope</body></html>')

      %w(private missing huge html).each do |host|
        post '/api/fetch-rss', params: { url: "https://#{host}.example/rss" }, as: :json

        expect(response).to have_http_status(500), host
        expect(response.parsed_body[:error]).to include(code: 'INTERNAL_ERROR', id: '5d37dbcb-891e-41ca-a3d6-e690c97775ac', kind: 'server'), host
      end
    end
  end

  describe 'fetch-external-resources' do
    let(:data) { "{\r\n  \"name\": \"Theme\"\r\n}" }
    let(:hash) { Digest::SHA512.hexdigest(data.gsub("\r\n", "\n")) }

    before do
      stub_request(:get, 'https://res.example/theme.json').to_return(status: 200, body: { type: 'theme', data: data }.to_json)
      stub_request(:get, 'https://res.example/bad.json').to_return(status: 200, body: { type: 'theme' }.to_json)
    end

    it 'returns the resource when the SHA-512 hash of its normalized data matches' do
      post '/api/fetch-external-resources', params: { i: token, url: 'https://res.example/theme.json', hash: hash }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to eq('type' => 'theme', 'data' => data)
    end

    it 'rejects mismatched hashes, invalid schemas, missing params and non-native tokens' do
      post '/api/fetch-external-resources', params: { i: token, url: 'https://res.example/theme.json', hash: 'wrong' }, as: :json
      expect(response.parsed_body[:error]).to include(code: 'EXT_RESOURCE_HASH_DIDNT_MATCH', id: '693ba8ba-b486-40df-a174-72f8279b56a4')

      post '/api/fetch-external-resources', params: { i: token, url: 'https://res.example/bad.json', hash: hash }, as: :json
      expect(response.parsed_body[:error]).to include(code: 'EXT_RESOURCE_RETURNED_INVALID_SCHEMA', id: 'bb774091-7a15-4a70-9dc5-6ac8cf125856')

      post '/api/fetch-external-resources', params: { i: token, url: 'https://res.example/theme.json' }, as: :json
      expect(response.parsed_body.dig(:error, :info, :param)).to eq('#/properties/hash')

      post '/api/fetch-external-resources', params: { i: app_token, url: 'https://res.example/theme.json', hash: hash }, as: :json
      expect(response).to have_http_status(403)

      post '/api/fetch-external-resources', params: { url: 'https://res.example/theme.json', hash: hash }, as: :json
      expect(response).to have_http_status(401)
    end
  end
end
