# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Clip statuses' do
  include_context 'with API authentication', oauth_scopes: 'read:lists write:lists'

  before { Setting.clips_enabled = true }

  describe 'GET /api/v1/clips/:clip_id/statuses' do
    let(:clip) { Fabricate(:clip, account: Fabricate(:account), public: true) }

    it 'uses the same authenticated read budget as the compatibility endpoint' do
      limiter = RateLimiter.new(user.account, family: :clip_notes)
      RateLimiter::FAMILIES[:clip_notes][:limit].times { limiter.record! }

      get "/api/v1/clips/#{clip.id}/statuses", headers: headers

      expect(response).to have_http_status(429)
      expect(response.headers['Cache-Control']).to eq('private, no-store')
      expect(response.headers['Retry-After'].to_i).to be_positive
    end
  end

  describe 'POST /api/v1/clips/:clip_id/statuses' do
    let(:clip) { Fabricate(:clip, account: user.account, public: false) }

    before { stub_const('Clip::STATUSES_LIMIT', 1) }

    it 'rejects a different status once the clip is full' do
      clip.clip_statuses.create!(status: Fabricate(:status))

      expect do
        post "/api/v1/clips/#{clip.id}/statuses", params: { status_id: Fabricate(:status).id }, headers: headers
      end.to_not change(ClipStatus, :count)

      expect(response).to have_http_status(422)
    end

    it 'remains idempotent for a status already in a full clip' do
      status = Fabricate(:status)
      clip.clip_statuses.create!(status: status)

      expect do
        post "/api/v1/clips/#{clip.id}/statuses", params: { status_id: status.id }, headers: headers
      end.to_not change(ClipStatus, :count)

      expect(response).to have_http_status(200)
    end
  end
end
