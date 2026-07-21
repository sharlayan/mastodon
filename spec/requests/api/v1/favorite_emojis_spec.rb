# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Favorite Emojis' do
  include_context 'with API authentication'

  let!(:custom_emoji) { Fabricate(:custom_emoji, shortcode: 'blobcat', disabled: false) }

  describe 'GET /api/v1/favorite_emojis' do
    let(:scopes) { 'read:accounts' }

    before do
      user.account.favorite_emojis.create!(name: 'blobcat', emoji_type: 'custom', position: 0)
    end

    it 'returns the favorites of the current account' do
      get api_v1_favorite_emojis_path, headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:name)).to eq(['blobcat'])
    end

    it 'returns http forbidden without a read scope' do
      get api_v1_favorite_emojis_path, headers: bearer_headers('write:accounts')

      expect(response).to have_http_status(403)
    end
  end

  describe 'POST /api/v1/favorite_emojis' do
    let(:scopes) { 'write:accounts' }

    it 'favorites an existing custom emoji' do
      post api_v1_favorite_emojis_path, params: { name: custom_emoji.shortcode, emoji_type: 'custom' }, headers: headers

      expect(response).to have_http_status(200)
      expect(user.account.favorite_emojis.pluck(:name)).to eq(['blobcat'])
    end

    it 'rejects unicode emojis' do
      post api_v1_favorite_emojis_path, params: { name: 'grinning', emoji_type: 'unicode' }, headers: headers

      expect(response).to have_http_status(422)
    end

    it 'rejects an unknown shortcode' do
      post api_v1_favorite_emojis_path, params: { name: 'nosuchemoji', emoji_type: 'custom' }, headers: headers

      expect(response).to have_http_status(422)
    end

    it 'returns http forbidden without a write scope' do
      post api_v1_favorite_emojis_path, params: { name: custom_emoji.shortcode, emoji_type: 'custom' }, headers: bearer_headers('read:accounts')

      expect(response).to have_http_status(403)
      expect(user.account.favorite_emojis).to_not exist
    end
  end

  describe 'DELETE /api/v1/favorite_emojis/:name' do
    let(:scopes) { 'write:accounts' }

    before do
      user.account.favorite_emojis.create!(name: 'blobcat', emoji_type: 'custom', position: 0)
    end

    it 'removes the favorite' do
      delete api_v1_favorite_emoji_path(name: 'blobcat'), headers: headers

      expect(response).to have_http_status(200)
      expect(user.account.favorite_emojis).to_not exist
    end

    it 'returns http forbidden without a write scope' do
      delete api_v1_favorite_emoji_path(name: 'blobcat'), headers: bearer_headers('read:accounts')

      expect(response).to have_http_status(403)
      expect(user.account.favorite_emojis).to exist
    end
  end

  def bearer_headers(token_scopes)
    { 'Authorization' => "Bearer #{Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: token_scopes).token}" }
  end
end
