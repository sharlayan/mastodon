# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Chat room deletion in roleplay mode' do
  include_context 'with an open chat policy'

  include_context 'with API authentication', oauth_scopes: 'read write'

  let(:service) { Sharlayan::ChatService.new }
  let(:member) { Fabricate(:user) }
  let(:room) { service.create_conversation(user.account, type: :group, title: 'Room') }

  around { |example| ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') { example.run } }

  before do
    Setting.chat_enabled = true
    Setting.misskey_compat_enabled = true
    room.memberships.create!(account: member.account)
    service.create_message(member.account, room, text: 'evidence')
  end

  after do
    Setting.chat_enabled = false
    Setting.misskey_compat_enabled = false
  end

  it 'refuses the owner through the native API' do
    delete "/api/v1/chat/conversations/#{room.id}", headers: headers

    expect(response).to have_http_status(422)
    expect(response.parsed_body[:error]).to eq(Sharlayan::ChatService::ROOM_DELETION_DISABLED)
    expect(ChatConversation).to exist(room.id)
    expect(room.messages.count).to eq(1)
  end

  it 'refuses the owner through the Misskey-compatible API' do
    post '/api/chat/rooms/delete', params: { roomId: MisskeyCompat::MiId.encode(room.id), i: token.token }, as: :json

    expect(response).to have_http_status(400)
    expect(ChatConversation).to exist(room.id)
  end

  it 'still refuses a member who is not the owner as forbidden' do
    expect { service.destroy_conversation(member.account, room) }.to raise_error(Sharlayan::ChatService::Forbidden)
  end

  it 'tells clients that rooms cannot be deleted' do
    get '/api/v1/chat/settings', headers: headers

    expect(response.parsed_body[:room_deletion]).to be(false)
  end

  it 'keeps permanent deletion by an administrator' do
    service.destroy_conversation_as_admin(room)

    expect(ChatConversation).to_not exist(room.id)
  end

  it 'keeps removing the rooms of a deleted account' do
    service.purge_account(user.account)

    expect(ChatConversation).to_not exist(room.id)
  end

  context 'when roleplay mode is off' do
    around { |example| ClimateControl.modify(OC_ROLEPLAY_OPTION: 'false') { example.run } }

    it 'lets the owner delete the room' do
      delete "/api/v1/chat/conversations/#{room.id}", headers: headers

      expect(response).to have_http_status(200)
      expect(ChatConversation).to_not exist(room.id)
    end

    it 'tells clients that rooms can be deleted' do
      get '/api/v1/chat/settings', headers: headers

      expect(response.parsed_body[:room_deletion]).to be(true)
    end
  end
end
