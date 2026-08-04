# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat chat compatibility endpoints' do
  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  it 'returns empty collections from every read-style compatibility endpoint' do
    endpoints = %w(
      chat/history
      chat/messages/user-timeline
      chat/messages/room-timeline
      chat/messages/search
      chat/rooms/owned
      chat/rooms/joining
      chat/rooms/members
      chat/rooms/invitations/inbox
      chat/rooms/invitations/outbox
    )

    endpoints.each do |endpoint|
      post "/api/#{endpoint}", as: :json

      expect(response).to have_http_status(200), endpoint
      expect(response.parsed_body).to eq([]), endpoint
    end
  end

  it 'returns empty objects from every object-style compatibility endpoint' do
    endpoints = %w(
      chat/read-all
      chat/messages/show
      chat/messages/create-to-room
      chat/messages/create-to-user
      chat/rooms/create
      chat/rooms/show
      chat/rooms/update
      chat/rooms/delete
      chat/rooms/mute
      chat/rooms/leave
      chat/rooms/join
      chat/rooms/invitations/create
      chat/rooms/invitations/ignore
    )

    endpoints.each do |endpoint|
      post "/api/#{endpoint}", as: :json

      expect(response).to have_http_status(200), endpoint
      expect(response.parsed_body).to eq({}), endpoint
    end
  end

  it 'keeps all chat compatibility endpoints behind the feature gate' do
    Setting.misskey_compat_enabled = false

    post '/api/chat/history', as: :json

    expect(response).to have_http_status(404)
    expect(response.parsed_body.dig(:error, :code)).to eq('ENDPOINT_DISABLED')
  end
end
