# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Clips' do
  include_context 'with API authentication', oauth_scopes: 'write:lists'

  before { Setting.clips_enabled = true }
  after { Setting.clips_enabled = false }

  describe 'POST /api/v1/clips' do
    it 'locks the account while validating the per-account limit' do
      queries = []
      callback = lambda do |_name, _started, _finished, _unique_id, payload|
        queries << payload[:sql] if payload[:name] != 'SCHEMA' && !payload[:cached]
      end

      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
        post '/api/v1/clips', headers: headers, params: { title: 'bounded clip' }
      end

      expect(response).to have_http_status(200)
      expect(queries.any? { |sql| sql.include?('FROM "accounts"') && sql.include?('FOR UPDATE') }).to be(true)
    end
  end

  describe 'GET /api/v1/clips/:id' do
    subject { get "/api/v1/clips/#{clip.id}", headers: headers }

    let(:clip) { Fabricate(:clip, public: public) }
    let(:public) { true }

    context 'without authentication' do
      let(:headers) { {} }

      it 'returns a public clip' do
        subject

        expect(response).to have_http_status(200)
        expect(response.parsed_body).to include('id' => clip.id.to_s)
      end

      context 'when the clip is private' do
        let(:public) { false }

        it 'returns http not found' do
          subject

          expect(response).to have_http_status(404)
        end
      end
    end

    context 'when the clip owner blocks the viewer' do
      let(:scopes) { 'read:lists' }

      before { clip.account.block!(user.account) }

      it 'hides the clip and does not list the owner clips' do
        subject

        expect(response).to have_http_status(404)

        get "/api/v1/accounts/#{clip.account_id}/clips", headers: headers

        expect(response).to have_http_status(200)
        expect(response.parsed_body).to be_empty
      end
    end

    context 'with a token missing the read lists scope' do
      let(:scopes) { 'read:accounts' }

      it_behaves_like 'forbidden for wrong scope', 'read:accounts'
    end
  end

  describe 'GET /api/v1/clips' do
    it 'requires authentication' do
      get '/api/v1/clips'

      expect(response).to have_http_status(401)
    end
  end

  describe 'owner-only actions on another account clip' do
    let(:other_clip) { Fabricate(:clip, account: Fabricate(:account), title: 'Original', public: true) }

    it 'does not update or delete the clip' do
      put "/api/v1/clips/#{other_clip.id}", params: { title: 'Hijacked', public: false }, headers: headers

      expect(response).to have_http_status(404)
      expect(other_clip.reload).to have_attributes(title: 'Original', public: true)

      delete "/api/v1/clips/#{other_clip.id}", headers: headers

      expect(response).to have_http_status(404)
      expect(Clip.exists?(other_clip.id)).to be(true)
    end
  end
end
