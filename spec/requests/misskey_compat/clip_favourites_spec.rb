# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat clip favourites' do
  let(:user)        { Fabricate(:user) }
  let(:other)       { Fabricate(:account) }
  let(:read_token)  { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read').token }
  let(:write_token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'write').token }

  before do
    Setting.misskey_compat_enabled = true
    Setting.clips_enabled = true
  end

  after do
    Setting.misskey_compat_enabled = false
    Setting.clips_enabled = false
  end

  describe 'POST /api/clips/favorite' do
    let(:clip) { Fabricate(:clip, account: other, public: true) }

    it 'favorites another account public clip' do
      expect do
        post '/api/clips/favorite', params: { i: write_token, clipId: MisskeyCompat::MiId.encode(clip.id) }, as: :json
      end.to change(ClipFavourite, :count).by(1)

      expect(response).to have_http_status(204)

      post '/api/clips/show', params: { i: read_token, clipId: MisskeyCompat::MiId.encode(clip.id) }, as: :json
      expect(response.parsed_body).to include(favoritedCount: 1, isFavorited: true)
    end

    it 'returns the Misskey duplicate favorite error' do
      user.account.clip_favourites.create!(clip: clip)

      post '/api/clips/favorite', params: { i: write_token, clipId: MisskeyCompat::MiId.encode(clip.id) }, as: :json

      expect(response).to have_http_status(400)
      expect(response.parsed_body.dig(:error, :code)).to eq('ALREADY_FAVORITED')
    end

    it 'does not expose another account private clip' do
      clip.update!(public: false)

      post '/api/clips/favorite', params: { i: write_token, clipId: MisskeyCompat::MiId.encode(clip.id) }, as: :json

      expect(response).to have_http_status(404)
      expect(response.parsed_body.dig(:error, :code)).to eq('NO_SUCH_CLIP')
    end
  end

  describe 'POST /api/clips/unfavorite' do
    let(:clip) { Fabricate(:clip, account: other, public: true) }

    it 'removes an existing favorite even after the clip becomes private' do
      user.account.clip_favourites.create!(clip: clip)
      clip.update!(public: false)

      expect do
        post '/api/clips/unfavorite', params: { i: write_token, clipId: MisskeyCompat::MiId.encode(clip.id) }, as: :json
      end.to change(ClipFavourite, :count).by(-1)

      expect(response).to have_http_status(204)
    end

    it 'returns the Misskey missing favorite error' do
      post '/api/clips/unfavorite', params: { i: write_token, clipId: MisskeyCompat::MiId.encode(clip.id) }, as: :json

      expect(response).to have_http_status(400)
      expect(response.parsed_body.dig(:error, :code)).to eq('NOT_FAVORITED')
    end
  end

  describe 'POST /api/clips/my-favorites' do
    let(:public_clip) { Fabricate(:clip, account: other, public: true) }
    let(:own_clip)    { Fabricate(:clip, account: user.account, public: false) }
    let(:hidden_clip) { Fabricate(:clip, account: other, public: true) }

    before do
      user.account.clip_favourites.create!(clip: public_clip)
      user.account.clip_favourites.create!(clip: own_clip)
      user.account.clip_favourites.create!(clip: hidden_clip)
      hidden_clip.update!(public: false)
    end

    it 'returns visible favorites, including another account public clip' do
      post '/api/clips/my-favorites', params: { i: read_token }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to contain_exactly(
        MisskeyCompat::MiId.encode(public_clip.id),
        MisskeyCompat::MiId.encode(own_clip.id)
      )
      expect(response.parsed_body).to all(include(favoritedCount: 1, isFavorited: true))
    end
  end
end
