# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Reacted statuses' do
  include_context 'with API authentication', oauth_scopes: 'read:favourites'

  describe 'GET /api/v1/reactions' do
    subject do
      get '/api/v1/reactions', headers: headers, params: params
    end

    let!(:thumbs) { Fabricate.times(2, :status_reaction, account: user.account, name: '👍', custom_emoji: nil) }

    before { Fabricate(:status_reaction, account: user.account, name: '🎉', custom_emoji: nil) }

    context 'with name and limit params' do
      let(:params) { { name: '👍', limit: 1 } }

      it 'keeps the name filter in the pagination links' do
        subject

        expect(response).to have_http_status(200)
        expect(response.parsed_body.pluck(:id)).to eq([thumbs.last.status_id.to_s])
        expect(response)
          .to include_pagination_headers(
            prev: api_v1_reactions_url(limit: 1, min_id: thumbs.last.id, name: '👍'),
            next: api_v1_reactions_url(limit: 1, max_id: thumbs.last.id, name: '👍')
          )
      end
    end

    context 'with local and remote custom emoji sharing a shortcode' do
      let!(:local_blob) { Fabricate(:status_reaction, account: user.account, name: 'blob', custom_emoji: Fabricate(:custom_emoji, shortcode: 'blob')) }
      let!(:remote_blob) { Fabricate(:status_reaction, account: user.account, name: 'blob', custom_emoji: Fabricate(:custom_emoji, shortcode: 'blob', domain: 'remote.tld')) }

      it 'filters the local emoji by its bare name' do
        get '/api/v1/reactions', headers: headers, params: { name: 'blob' }

        expect(response.parsed_body.pluck(:id)).to eq([local_blob.status_id.to_s])
      end

      it 'filters the remote emoji by name and domain' do
        get '/api/v1/reactions', headers: headers, params: { name: 'blob@remote.tld' }

        expect(response.parsed_body.pluck(:id)).to eq([remote_blob.status_id.to_s])
      end
    end
  end
end
