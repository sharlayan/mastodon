# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Media Proxy' do
  describe 'GET /proxy' do
    before do
      Setting.misskey_compat_enabled = true
      Rails.cache.clear
    end

    after { Setting.misskey_compat_enabled = false }

    it 'redirects to a URL already known through a preview card' do
      card = Fabricate(:preview_card, url: 'https://known.example/article')

      get '/proxy', params: { url: card.url }

      expect(response).to redirect_to(card.url)
    end

    it 'keeps redirecting known URLs that exceed the common 2 KiB boundary' do
      card = Fabricate(:preview_card, url: "https://known.example/#{'a' * 2_100}")

      get '/proxy', params: { url: card.url }

      expect(response).to redirect_to(card.url)
    end

    it 'redirects to a URL already known through a remote media attachment' do
      attachment = Fabricate(:media_attachment, remote_url: 'https://known.example/image.png')

      get '/proxy', params: { url: attachment.remote_url }

      expect(response).to redirect_to(attachment.remote_url)
    end

    it 'redirects to a custom favicon advertised for an instance' do
      metadata = InstanceMetadata.create!(domain: 'remote.example', favicon_url: 'https://cdn.example/remote.ico')

      get '/proxy/image.webp', params: { url: metadata.favicon_url, preview: 1 }

      expect(response).to redirect_to(metadata.favicon_url)
    end

    it 'redirects to a locally cached instance favicon exposed as an absolute asset URL' do
      metadata = InstanceMetadata.create!(domain: 'remote.example', favicon_url: '/system/instance_favicons/remote.png')
      favicon_url = Class.new do
        include RoutingHelper
      end.new.full_asset_url(metadata.favicon_url)

      get '/proxy/image.webp', params: { url: favicon_url, fallback: 1 }

      expect(response).to redirect_to(favicon_url)
    end

    it 'redirects to the fallback favicon emitted for a known remote account' do
      account = Fabricate(:account, domain: 'remote.example')
      favicon_url = "https://#{account.domain}/favicon.ico"

      get '/proxy/image.webp', params: { url: favicon_url, preview: 1 }

      expect(response).to redirect_to(favicon_url)
    end

    it 'does not treat a favicon-shaped URL for an unknown domain as known' do
      get '/proxy/image.webp', params: { url: 'https://unknown.example/favicon.ico', preview: 1 }

      expect(response).to have_http_status(404)
    end

    it 'redirects to a locally stored custom emoji image' do
      emoji = Fabricate(:custom_emoji, shortcode: 'coolcat')
      emoji_url = Class.new { include RoutingHelper }.new.full_asset_url(emoji.image.url)

      get '/proxy/image.webp', params: { url: emoji_url, emoji: 1, origin: 1 }

      expect(response).to redirect_to(emoji_url)
    end

    it 'redirects to the static style of a custom emoji image' do
      emoji = Fabricate(:custom_emoji, shortcode: 'coolcat')
      emoji_url = Class.new { include RoutingHelper }.new.full_asset_url(emoji.image.url(:static))

      get '/proxy/static.webp', params: { url: emoji_url, static: 1 }

      expect(response).to redirect_to(emoji_url)
    end

    it 'redirects to the original URL recorded for a remote custom emoji' do
      emoji = Fabricate(:custom_emoji, shortcode: 'coolcat', domain: 'remote.example', uri: 'https://remote.example/emoji/coolcat')
      emoji.update_column(:image_remote_url, 'https://remote.example/emoji/coolcat.png')

      get '/proxy/image.webp', params: { url: emoji.image_remote_url, emoji: 1 }

      expect(response).to redirect_to(emoji.image_remote_url)
    end

    it 'does not treat an emoji-shaped asset path for an unknown id as known' do
      get '/proxy/image.webp', params: { url: Class.new { include RoutingHelper }.new.full_asset_url('/system/custom_emojis/images/000/999/999/original/nope.png'), emoji: 1 }

      expect(response).to have_http_status(404)
    end

    it 'does not redirect to an arbitrary external URL' do
      get '/proxy', params: { url: 'https://attacker.example/phishing' }

      expect(response).to have_http_status(404)
    end

    it 'rejects oversized URLs before querying known resources' do
      allow(PreviewCard).to receive(:exists?).and_call_original

      get '/proxy', params: { url: "https://unknown.example/#{'a' * MisskeyCompat::MediaProxyController::MAX_URL_BYTES}" }

      expect(response).to have_http_status(404)
      expect(PreviewCard).to_not have_received(:exists?)
    end

    it 'negative-caches an unknown URL' do
      allow(PreviewCard).to receive(:exists?).and_call_original
      url = 'https://unknown.example/repeated-miss.png'

      2.times { get '/proxy', params: { url: url } }

      expect(response).to have_http_status(404)
      expect(PreviewCard).to have_received(:exists?).once
    end
  end

  describe 'GET /media_proxy/:id' do
    before { stub_attachment_request }

    context 'when attached to a status' do
      let(:status) { Fabricate(:status) }
      let(:media_attachment) { Fabricate(:media_attachment, status: status, remote_url: 'http://example.com/attachment.png') }

      it 'redirects to correct original url' do
        get "/media_proxy/#{media_attachment.id}"

        expect(response)
          .to have_http_status(302)
          .and redirect_to media_attachment.file.url(:original)
      end

      it 'redirects to small style url' do
        get "/media_proxy/#{media_attachment.id}/small"

        expect(response)
          .to have_http_status(302)
          .and redirect_to media_attachment.file.url(:small)
      end
    end

    context 'when the media attachment is a Drive pointer' do
      let(:account) { Fabricate(:account) }
      let(:status) { Fabricate(:status, account: account) }
      let(:drive_file) { account.drive_files.create!(file: attachment_fixture('attachment.jpg')) }
      let(:media_attachment) do
        drive_file.build_pointer(account).tap do |pointer|
          pointer.status = status
          pointer.save!
        end
      end

      it 'redirects original and preview requests to the Drive resolver' do
        get "/media_proxy/#{media_attachment.id}"
        expect(response).to redirect_to(%r{/drive_media/#{media_attachment.drive_access_key}/original\z})

        get "/media_proxy/#{media_attachment.id}/small"
        expect(response).to redirect_to(%r{/drive_media/#{media_attachment.drive_access_key}/small\z})
      end
    end

    context 'when there is not an attached status' do
      let(:media_attachment) { Fabricate(:media_attachment, status: status, remote_url: 'http://example.com/attachment.png') }

      it 'responds with missing' do
        get "/media_proxy/#{media_attachment.id}"

        expect(response)
          .to have_http_status(404)
      end
    end

    context 'when id cannot be found' do
      it 'responds with missing' do
        get '/media_proxy/missing'

        expect(response)
          .to have_http_status(404)
      end
    end

    context 'when not permitted to view' do
      let(:status) { Fabricate(:status, visibility: :direct) }
      let(:media_attachment) { Fabricate(:media_attachment, status: status, remote_url: 'http://example.com/attachment.png') }

      it 'responds with missing' do
        get "/media_proxy/#{media_attachment.id}"

        expect(response)
          .to have_http_status(404)
      end
    end

    context 'when an admin wants to see a suspended attachment' do
      before do
        sign_in Fabricate(:admin_user)
      end

      let(:account) { Fabricate(:account, suspended: true) }
      let(:status) { Fabricate(:status, account:) }
      let(:media_attachment) { Fabricate(:media_attachment, account:, status:, type: :image) }

      it 'returns the media' do
        get "/media_proxy/#{media_attachment.id}"

        expect(response).to have_http_status(200)
      end
    end

    def stub_attachment_request
      stub_request(
        :get,
        'http://example.com/attachment.png'
      )
        .to_return(
          request_fixture('avatar.txt')
        )
    end
  end
end
