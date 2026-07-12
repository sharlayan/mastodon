# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat emoji endpoint' do
  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  describe 'POST /api/emoji' do
    before { Fabricate(:custom_emoji, shortcode: 'coolcat') }

    it 'returns the single emoji detail with an id' do
      post '/api/emoji', params: { name: 'coolcat' }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to include(name: 'coolcat', host: nil)
      expect(response.parsed_body[:id]).to be_present
      expect(response.parsed_body[:url]).to be_present
    end

    it 'tolerates surrounding colons' do
      post '/api/emoji', params: { name: ':coolcat:' }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:name]).to eq('coolcat')
    end

    it 'returns a Misskey error envelope when the emoji is unknown' do
      post '/api/emoji', params: { name: 'nope' }, as: :json

      expect(response).to have_http_status(404)
      expect(response.parsed_body[:error]).to include(code: 'NO_SUCH_EMOJI')
    end
  end
end
