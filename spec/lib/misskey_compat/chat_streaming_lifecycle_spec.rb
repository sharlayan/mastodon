# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Chat streaming lifecycle', type: :model do
  let(:owner) { Fabricate(:user).account }
  let(:member) { Fabricate(:user).account }
  let(:remote) { Fabricate(:account, domain: 'chat.example', can_chat: true, chat_scope: 'everyone') }
  let(:service) { Sharlayan::ChatService.new }
  let(:events) { [] }

  before do
    Setting.chat_enabled = true
    Setting.chat_federation_enabled = true
    allow(redis).to receive(:publish) { |channel, payload| events << [channel, JSON.parse(payload)] }
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_federation_enabled = false
  end

  def native_events(type)
    events.filter_map { |channel, event| JSON.parse(event['payload']) if channel == "timeline:#{owner.id}" && event['event'] == type }
  end

  it 'publishes one reaction for a retry and publishes a later re-add again' do
    room = service.create_conversation(owner, type: :direct, account_ids: [remote.id])
    message = service.create_message(owner, room, text: 'hello')
    first_id = 'https://chat.example/react/first'
    service.react_remote(remote, message, '👍', activity_id: first_id)
    service.react_remote(remote, message, '👍', activity_id: first_id)

    expect(native_events('chat.reaction').size).to eq(1)

    service.unreact_remote(remote, message, '👍', activity_id: first_id)
    service.react_remote(remote, message, '👍', activity_id: 'https://chat.example/react/second')
    expect(native_events('chat.reaction').size).to eq(2)
  end

  it 'announces the actual account after accepting a local invitation' do
    room = service.create_conversation(owner, type: :group, title: 'Room')
    invitation = service.invite(owner, room, member)

    service.accept_invitation(member, invitation)

    expect(native_events('chat.member_join')).to contain_exactly('conversation_id' => room.id.to_s, 'account_id' => member.id.to_s)
  end

  it 'announces a remote acceptance to local room members' do
    room = service.create_conversation(owner, type: :group, title: 'Room')
    service.invite(owner, room, remote)

    service.receive_accept(remote, room_uri: room.uri)

    expect(native_events('chat.member_join')).to contain_exactly('conversation_id' => room.id.to_s, 'account_id' => remote.id.to_s)
  end

  it 'announces a remote roster addition only once across retries' do
    room = service.receive_invite(owner, remote, room_uri: 'https://chat.example/room', title: 'Remote room').chat_conversation
    service.accept_invitation(owner, room.invitations.pending.first)
    added = Fabricate(:account, domain: 'other.example')
    events.clear

    2.times { service.receive_add(remote, room_uri: room.uri, account_uri: added.uri) }

    expect(native_events('chat.member_join')).to contain_exactly('conversation_id' => room.id.to_s, 'account_id' => added.id.to_s)
  end
end
