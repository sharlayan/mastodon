# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Status drafts' do
  include_context 'with API authentication', oauth_scopes: 'read:statuses write:statuses'

  describe 'POST /api/v1/status_drafts' do
    let(:media) { Fabricate(:media_attachment, account: user.account) }

    it 'stores compose state and protects its media from orphan cleanup', :aggregate_failures do
      post '/api/v1/status_drafts', headers: headers, params: {
        status: 'Work in progress',
        spoiler_text: 'CW',
        visibility: 'private',
        media_ids: [media.id],
        poll: { options: %w(One Two), multiple: true, expires_in: 3600 },
      }

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:params]).to include(status: 'Work in progress', spoiler_text: 'CW', visibility: 'private')
      expect(response.parsed_body[:media_attachments].pluck(:id)).to eq([media.id.to_s])
      expect(media.reload.status_draft_id).to eq(StatusDraft.last.id)
      expect(MediaAttachment.unattached).to_not include(media)
    end

    it 'rejects media belonging to another account' do
      other_media = Fabricate(:media_attachment)

      expect do
        post '/api/v1/status_drafts', headers: headers, params: { status: 'No', media_ids: [other_media.id] }
      end.to_not change(StatusDraft, :count)

      expect(response).to have_http_status(404)
    end

    it 'rejects oversized draft data' do
      post '/api/v1/status_drafts', headers: headers, params: { status: 'x' * StatusDraft::MAX_DATA_BYTES }

      expect(response).to have_http_status(422)
      expect(user.account.status_drafts).to_not exist
    end
  end

  describe 'owner isolation and updates' do
    let!(:draft) { Fabricate(:status_draft, account: user.account) }
    let(:other_user) { Fabricate(:user) }
    let(:other_token) { Fabricate(:accessible_access_token, resource_owner_id: other_user.id, scopes: scopes) }
    let(:other_headers) { { 'Authorization' => "Bearer #{other_token.token}" } }

    it 'lists only the current account drafts' do
      Fabricate(:status_draft)
      get '/api/v1/status_drafts', headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to contain_exactly(draft.id.to_s)
    end

    it 'updates a draft owned by the current account' do
      put "/api/v1/status_drafts/#{draft.id}", headers: headers, params: { status: 'Updated' }

      expect(response).to have_http_status(200)
      expect(draft.reload.data['status']).to eq('Updated')
    end

    it 'does not expose another account draft' do
      get "/api/v1/status_drafts/#{draft.id}", headers: other_headers

      expect(response).to have_http_status(404)
    end

    it 'deletes a draft and releases its media' do
      media = Fabricate(:media_attachment, account: user.account, status_draft: draft)
      delete "/api/v1/status_drafts/#{draft.id}", headers: headers

      expect(response).to have_http_status(200)
      expect(media.reload.status_draft_id).to be_nil
    end

    it 'caps lists and excludes oversized legacy drafts' do
      draft.update_column(:data, { status: 'x' * StatusDraft::MAX_DATA_BYTES })
      StatusDraft::LIST_LIMIT.times { Fabricate(:status_draft, account: user.account) }

      get '/api/v1/status_drafts', headers: headers, params: { limit: 100 }

      expect(response).to have_http_status(200)
      expect(response.parsed_body.size).to eq(StatusDraft::LIST_LIMIT)
      expect(response.parsed_body.pluck(:id)).to_not include(draft.id.to_s)
    end

    it 'refuses to serialize an oversized legacy draft' do
      draft.update_column(:data, { status: 'x' * StatusDraft::MAX_DATA_BYTES })

      get "/api/v1/status_drafts/#{draft.id}", headers: headers

      expect(response).to have_http_status(422)
    end

    it 'enforces a dedicated per-account request limit' do
      RateLimiter::FAMILIES[:status_drafts][:limit].times do
        RateLimiter.new(user.account, family: :status_drafts).record!
      end

      get '/api/v1/status_drafts', headers: headers

      expect(response).to have_http_status(429)
    end
  end
end
