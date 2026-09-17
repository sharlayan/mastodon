# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Clip statuses' do
  include_context 'with API authentication', oauth_scopes: 'read:lists write:lists'

  before { Setting.clips_enabled = true }

  describe 'GET /api/v1/clips/:clip_id/statuses' do
    subject { get "/api/v1/clips/#{clip.id}/statuses", headers: headers }

    let(:clip) { Fabricate(:clip, account: Fabricate(:account), public: public) }
    let(:public) { true }

    it 'uses the same authenticated read budget as the compatibility endpoint' do
      limiter = RateLimiter.new(user.account, family: :clip_notes)
      RateLimiter::FAMILIES[:clip_notes][:limit].times { limiter.record! }

      subject

      expect(response).to have_http_status(429)
      expect(response.headers['Cache-Control']).to eq('private, no-store')
      expect(response.headers['Retry-After'].to_i).to be_positive
    end

    context 'without authentication' do
      let(:headers) { {} }

      it 'returns statuses from a public clip' do
        status = Fabricate(:status)
        clip.clip_statuses.create!(status: status)

        subject

        expect(response).to have_http_status(200)
        expect(response.parsed_body.pluck('id')).to include(status.id.to_s)
      end

      context 'when the clip is private' do
        let(:public) { false }

        it 'returns http not found' do
          subject

          expect(response).to have_http_status(404)
        end
      end
    end

    context 'with a token missing the read lists scope' do
      let(:scopes) { 'read:accounts' }

      it_behaves_like 'forbidden for wrong scope', 'read:accounts'
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
