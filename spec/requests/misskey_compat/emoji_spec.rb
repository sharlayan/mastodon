# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat emoji endpoint' do
  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  describe 'POST /api/emoji' do
    before { Fabricate(:custom_emoji, shortcode: 'coolcat') }

    it 'returns the single emoji detail with an id' do
      post '/api/emoji', params: { name: 'coolcat' }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to include(name: 'coolcat', host: nil)
      expect(response.parsed_body[:id]).to be_present
      expect(response.parsed_body[:url]).to be_present
    end

    it 'tolerates surrounding colons' do
      post '/api/emoji', params: { name: ':coolcat:' }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:name]).to eq('coolcat')
    end

    it 'returns a Misskey error envelope when the emoji is unknown' do
      post '/api/emoji', params: { name: 'nope' }, as: :json

      expect(response).to have_http_status(404)
      expect(response.parsed_body[:error]).to include(code: 'NO_SUCH_EMOJI')
    end
  end

  describe 'POST /api/emojis' do
    it 'lists local emoji that are usable but hidden from the picker' do
      Fabricate(:custom_emoji, shortcode: 'hidden', visible_in_picker: false)
      Fabricate(:custom_emoji, shortcode: 'remote', domain: 'remote.example', uri: 'https://remote.example/emoji/remote')
      Fabricate(:custom_emoji, shortcode: 'off', disabled: true)

      post '/api/emojis', as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:emojis].pluck(:name)).to contain_exactly('hidden')
    end
  end

  describe 'GET /emoji/:name' do
    let(:asset_host) { Class.new { include RoutingHelper }.new }

    it 'redirects a local emoji request to the image' do
      emoji = Fabricate(:custom_emoji, shortcode: 'coolcat')

      get '/emoji/coolcat.webp'

      expect(response).to redirect_to(asset_host.full_asset_url(emoji.image.url(:original)))
      expect(response).to have_http_status(302)
    end

    it 'accepts the Misskey local host marker' do
      emoji = Fabricate(:custom_emoji, shortcode: 'coolcat')

      get '/emoji/coolcat@..webp'

      expect(response).to redirect_to(asset_host.full_asset_url(emoji.image.url(:original)))
    end

    it 'resolves a remote emoji by host' do
      emoji = Fabricate(:custom_emoji, shortcode: 'coolcat', domain: 'remote.example', uri: 'https://remote.example/emoji/coolcat')

      get '/emoji/coolcat@remote.example.webp'

      expect(response).to redirect_to(asset_host.full_asset_url(emoji.image.url(:original)))
    end

    it 'serves the static style when asked' do
      emoji = Fabricate(:custom_emoji, shortcode: 'coolcat')

      get '/emoji/coolcat.webp', params: { static: 1 }

      expect(response).to redirect_to(asset_host.full_asset_url(emoji.image.url(:static)))
    end

    it 'does not resolve a local name as a remote emoji' do
      Fabricate(:custom_emoji, shortcode: 'coolcat')

      get '/emoji/coolcat@remote.example.webp'

      expect(response).to have_http_status(404)
    end

    it 'rejects a disabled emoji' do
      Fabricate(:custom_emoji, shortcode: 'coolcat', disabled: true)

      get '/emoji/coolcat.webp'

      expect(response).to have_http_status(404)
    end

    it 'rejects a name with more than one host separator' do
      get '/emoji/coolcat@remote.example@evil.example.webp'

      expect(response).to have_http_status(400)
    end

    it 'is unavailable while misskey compatibility is disabled' do
      Fabricate(:custom_emoji, shortcode: 'coolcat')
      Setting.misskey_compat_enabled = false

      get '/emoji/coolcat.webp'

      expect(response).to have_http_status(404)
    end
  end
end
