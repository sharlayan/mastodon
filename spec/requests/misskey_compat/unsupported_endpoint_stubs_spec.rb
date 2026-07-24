# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat unsupported endpoint stubs' do
  let(:object_endpoints) do
    %w(
      app/create
      app/show
      chat/messages/create-to-room
      chat/messages/create-to-user
      chat/rooms/create
      flash/create
      ping
      reversi/match
      reversi/show-game
      reversi/verify
      test
      v2/admin/emoji/list
    )
  end

  let(:array_endpoints) do
    %w(
      bubble-game/ranking
      chat/messages/search
      retention
      reversi/games
      reversi/invitations
    )
  end

  let(:void_endpoints) do
    %w(
      bubble-game/register
      chat/messages/delete
      chat/messages/react
      chat/messages/unreact
      flash/delete
      promo/read
      request-reset-password
      reset-db
      reset-password
      reversi/cancel-match
      reversi/surrender
    )
  end

  let(:explicitly_unsupported_endpoints) do
    %w(
      channels/create
      channels/favorite
      channels/featured
      channels/follow
      channels/followed
      channels/mute/create
      channels/mute/delete
      channels/mute/list
      channels/my-favorites
      channels/owned
      channels/search
      channels/show
      channels/timeline
      channels/unfavorite
      channels/unfollow
      channels/update
      gallery/featured
      gallery/popular
      gallery/posts
      gallery/posts/create
      gallery/posts/delete
      gallery/posts/like
      gallery/posts/show
      gallery/posts/unlike
      gallery/posts/update
      i/gallery/likes
      i/gallery/posts
      sw/update-registration
      username/available
      users/gallery/posts
      verify-email
    )
  end

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  it 'returns an empty object from every object stub' do
    object_endpoints.each do |endpoint|
      post "/api/#{endpoint}", as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to eq({})
    end
  end

  it 'returns an empty array from every array stub' do
    array_endpoints.each do |endpoint|
      post "/api/#{endpoint}", as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to eq([])
    end
  end

  it 'returns no content from every void stub' do
    void_endpoints.each do |endpoint|
      post "/api/#{endpoint}", as: :json

      expect(response).to have_http_status(204)
      expect(response.body).to be_empty
    end
  end

  it 'returns a Misskey error envelope from explicitly unsupported endpoints' do
    explicitly_unsupported_endpoints.each do |endpoint|
      post "/api/#{endpoint}", as: :json

      expect(response).to have_http_status(501)
      expect(response.parsed_body[:error]).to include(code: 'UNSUPPORTED_ENDPOINT', kind: 'server')
    end
  end

  it 'advertises every named unsupported endpoint stub' do
    post '/api/endpoints', as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body).to include(*(object_endpoints + array_endpoints + void_endpoints + explicitly_unsupported_endpoints))
  end
end
