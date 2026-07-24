# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat meta endpoint' do
  before  { Setting.misskey_compat_enabled = true }
  after   { Setting.misskey_compat_enabled = false }

  describe 'POST /api/meta' do
    before do
      allow(ViteRuby.instance.manifest)
        .to receive(:path_for)
        .with('icons/android-chrome-512x512.png')
        .and_return('/packs/default-server-icon.png')
    end

    it 'returns detailed meta by default with the fields Flare requires' do
      post '/api/meta', params: {}, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to include(:name, :uri, :maxNoteTextLength, :policies, :features, :requireSetup)
      expect(response.parsed_body[:iconUrl]).to end_with('/packs/default-server-icon.png')
      expect(response.parsed_body[:features]).to include(miauth: true)
      expect(response.parsed_body[:clientOptions]).to include(
        entrancePageStyle: 'classic',
        showTimelineForVisitor: true,
        showActivitiesForVisitor: true
      )
    end

    it 'returns lite meta without detailed keys when detail is false' do
      post '/api/meta', params: { detail: false }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to include(:name)
      expect(response.parsed_body).to_not include(:features)
    end

    it 'prefers the app icon configured by the Mastodon administrator' do
      app_icon = Fabricate(:site_upload, var: 'app_icon')
      Rails.cache.delete('site_uploads/app_icon')

      post '/api/meta', params: {}, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:iconUrl]).to end_with(app_icon.file.url(:original))
    end

    it 'mirrors Misskey INVALID_PARAM when the body is not an object' do
      post '/api/meta', params: '[]', headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(400)
      expect(response.parsed_body[:error]).to include(
        message: 'Invalid param.',
        code: 'INVALID_PARAM',
        id: '3d81ceae-475f-4600-b2a8-2bc116157532',
        kind: 'client'
      )
      expect(response.parsed_body.deep_symbolize_keys[:error][:info]).to eq(param: '#/type', reason: 'must be object')
    end

    it 'mirrors Misskey INVALID_PARAM when detail has the wrong type' do
      post '/api/meta', params: { detail: 'nope' }, as: :json

      expect(response).to have_http_status(400)
      expect(response.parsed_body.deep_symbolize_keys.dig(:error, :info)).to eq(param: '#/properties/detail/type', reason: 'must be boolean')
    end
  end

  describe 'when the compat layer is disabled' do
    before { Setting.misskey_compat_enabled = false }

    it 'returns 404' do
      post '/api/meta', params: {}, as: :json

      expect(response).to have_http_status(404)
    end
  end
end
