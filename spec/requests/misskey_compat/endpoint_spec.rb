# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat endpoint endpoint' do
  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  describe 'POST /api/endpoint' do
    it 'returns an empty params list for a known endpoint and an error envelope for an unadvertised endpoint' do
      post '/api/endpoint', params: { endpoint: 'notes/create' }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to eq('params' => [])

      post '/api/endpoint', params: { endpoint: 'notes/drafts/show' }, as: :json

      expect(response).to have_http_status(404)
      expect(response.parsed_body[:error]).to include(code: 'NO_SUCH_ENDPOINT')
    end
  end
end
