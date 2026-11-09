# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Custom emoji in chat text' do
  let(:user) { Fabricate(:user) }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read:statuses').token }
  let(:headers) { { 'Authorization' => "Bearer #{token}" } }
  let!(:emoji) { Fabricate(:custom_emoji, shortcode: 'blobcat') }
  let(:room) do
    ChatConversation.create!(conversation_type: :group, owner_account: user.account, title: 'Cats :blobcat:').tap do |room|
      room.memberships.create!(account: user.account, role: :owner)
      message = room.messages.create!(account: user.account, text: 'hello :blobcat:')
      room.update!(last_message: message)
    end
  end

  before { Setting.chat_enabled = true }
  after { Setting.chat_enabled = false }

  it 'lists the emoji of the room title and of the last message' do
    room

    get '/api/v1/chat/conversations', headers: headers

    entry = response.parsed_body.first
    expect(entry['emojis'].pluck('shortcode')).to eq(['blobcat'])
    expect(entry['last_message']['emojis'].pluck('shortcode')).to eq(['blobcat'])
  end

  it 'lists the emoji of each message' do
    get "/api/v1/chat/conversations/#{room.id}/messages", headers: headers

    expect(response.parsed_body.first['emojis'].first).to include('shortcode' => emoji.shortcode, 'url' => a_string_including('http'))
  end

  it 'lists no emoji for a deleted message' do
    room.last_message.update!(text: nil, deleted_at: Time.current)

    get "/api/v1/chat/conversations/#{room.id}/messages", headers: headers

    expect(response.parsed_body.first['emojis']).to eq([])
  end
end
