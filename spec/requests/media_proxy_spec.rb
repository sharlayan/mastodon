# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Media Proxy' do
  describe 'GET /proxy' do
    before { Setting.misskey_compat_enabled = true }
    after { Setting.misskey_compat_enabled = false }

    it 'redirects to a URL already known through a preview card' do
      card = Fabricate(:preview_card, url: 'https://known.example/article')

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

    it 'does not redirect to an arbitrary external URL' do
      get '/proxy', params: { url: 'https://attacker.example/phishing' }

      expect(response).to have_http_status(404)
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
