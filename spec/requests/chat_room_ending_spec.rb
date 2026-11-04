# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'What became of a chat room' do
  include_context 'with an open chat policy'

  include_context 'with API authentication', oauth_scopes: 'read write'

  let(:service) { Sharlayan::ChatService.new }
  let(:member) { Fabricate(:user) }
  let(:room) { service.create_conversation(user.account, type: :group, title: 'Room') }
  let(:remote_owner) do
    Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/owner', inbox_url: 'https://remote.test/users/owner/inbox', can_chat: true, chat_scope: 'everyone')
  end

  before do
    Setting.chat_enabled = true
    Setting.chat_federation_enabled = true
    room.memberships.create!(account: member.account)
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_federation_enabled = false
  end

  def open_room(id, as: member)
    token.update!(resource_owner_id: as.id)
    get "/api/v1/chat/conversations/#{id}", headers: headers
  end

  def join_copy_of_remote_room(name)
    conversation = service.receive_invite(member.account, remote_owner, room_uri: "https://remote.test/chat/rooms/#{name}", title: 'Room').chat_conversation
    service.accept_invitation(member.account, conversation.invitations.find_by!(invitee_account: member.account))
    conversation
  end

  it 'tells a member who was removed' do
    service.kick(user.account, room, member.account)

    open_room(room.id)

    expect(response).to have_http_status(404)
    expect(response.parsed_body).to include(reason: 'removed')
  end

  it 'tells a member who left' do
    service.leave(member.account, room)

    open_room(room.id)

    expect(response).to have_http_status(404)
    expect(response.parsed_body).to include(reason: 'removed')
  end

  it 'tells a member and the owner when the group was deleted' do
    room_id = room.id
    service.destroy_conversation(user.account, room)

    open_room(room_id)
    expect(response.parsed_body).to include(reason: 'deleted')

    open_room(room_id, as: user)
    expect(response.parsed_body).to include(reason: 'deleted')
  end

  it 'tells someone who was removed that the group was deleted later' do
    room_id = room.id
    service.kick(user.account, room, member.account)
    service.destroy_conversation(user.account, room)

    open_room(room_id)

    expect(response.parsed_body).to include(reason: 'deleted')
  end

  it 'does not tell anyone else that the group ever existed' do
    outsider = Fabricate(:user)
    room_id = room.id
    service.destroy_conversation(user.account, room)

    open_room(room_id, as: outsider)

    expect(response).to have_http_status(404)
    expect(response.parsed_body).to_not have_key(:reason)
  end

  it 'keeps the room open for someone who came back' do
    service.kick(user.account, room, member.account)
    room.memberships.create!(account: member.account)

    open_room(room.id)

    expect(response).to have_http_status(200)
  end

  it 'says nothing about a direct chat that went with an account' do
    direct = service.create_conversation(user.account, type: :direct, account_ids: [member.account.id])
    direct_id = direct.id
    service.send(:destroy_and_announce, direct)

    open_room(direct_id)

    expect(response).to have_http_status(404)
    expect(response.parsed_body).to_not have_key(:reason)
  end

  it 'keeps saying removed when the copy of a remote room goes with its last member here' do
    conversation = join_copy_of_remote_room('removed')
    conversation_id = conversation.id
    service.receive_remove(remote_owner, room_uri: conversation.uri, account_uri: ActivityPub::TagManager.instance.uri_for(member.account))
    conversation.destroy_if_unused!
    expect(ChatConversation.exists?(conversation_id)).to be(false)

    open_room(conversation_id)

    expect(response.parsed_body).to include(reason: 'removed')
  end

  it 'tells a member when the remote owner deleted the group' do
    conversation = join_copy_of_remote_room('deleted')
    conversation_id = conversation.id
    service.receive_remove(remote_owner, room_uri: conversation.uri, account_uri: remote_owner.uri)

    open_room(conversation_id)

    expect(response.parsed_body).to include(reason: 'deleted')
  end

  it 'announces the reason on the stream, but not to whoever deleted the group' do
    allow(service).to receive(:broadcast_to)
    service.destroy_conversation(user.account, room)

    expect(service).to have_received(:broadcast_to).with(user.account, 'chat.conversation_delete', { conversation_id: room.id.to_s })
    expect(service).to have_received(:broadcast_to).with(member.account, 'chat.conversation_delete', { conversation_id: room.id.to_s, reason: 'deleted' })
  end
end
