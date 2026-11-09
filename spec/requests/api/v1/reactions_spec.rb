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
  end
end
