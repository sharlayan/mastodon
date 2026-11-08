# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MisskeyCompat::ChatStreaming do
  include_context 'with an open chat policy'

  let(:owner) { Fabricate(:user).account }
  let(:member) { Fabricate(:user).account }
  let(:service) { Sharlayan::ChatService.new }
  let(:events) { [] }

  before do
    Setting.chat_enabled = true
    Setting.misskey_compat_enabled = true
    allow(redis).to receive(:publish) { |channel, payload| events << [channel, JSON.parse(payload)] }
  end

  after do
    Setting.chat_enabled = false
    Setting.misskey_compat_enabled = false
    Setting.chat_soft_delete_enabled = false
  end

  def mid(record)
    MisskeyCompat::MiId.encode(record.id)
  end

  def subscribe(channel)
    redis.setex("subscribed:misskey:chatClient:#{channel.split(':')[1]}", 60, '1')
    redis.setex("subscribed:misskey:#{channel}", 60, '1')
  end

  def chat_queries(pattern = /FROM "chat_/, &block)
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] if !payload[:cached] && payload[:sql].match?(pattern) }
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &block)
    queries
  end

  def payloads(channel)
    events.filter_map { |key, value| value['payload'] if key == "misskey:#{channel}" }
  end

  it 'delivers direct messages to both viewers and keeps native streaming intact' do
    room = service.create_conversation(owner, type: :direct, account_ids: [member.id])
    subscribe("chatUser:#{owner.id}:#{member.id}")
    subscribe("chatUser:#{member.id}:#{owner.id}")
    subscribe("chatMain:#{member.id}")

    message = service.create_message(owner, room, text: 'hello')

    expect(payloads("chatUser:#{owner.id}:#{member.id}").first).to include('type' => 'message', 'body' => include('id' => mid(message), 'text' => 'hello', 'fromUserId' => mid(owner), 'toUserId' => mid(member)))
    expect(payloads("chatUser:#{member.id}:#{owner.id}").first.dig('body', 'id')).to eq(mid(message))
    expect(payloads("chatMain:#{member.id}").first).to include('type' => 'newChatMessage', 'body' => include('id' => mid(message)))
    expect(events).to include(["timeline:#{owner.id}", include('event' => 'chat.message')])
  end

  it 'publishes group mutations in the event shapes consumed by CherryPick' do
    room = service.create_conversation(owner, type: :group, title: 'Room')
    room.memberships.create!(account: member)
    channel = "chatRoom:#{member.id}:#{room.id}"
    subscribe(channel)
    message = service.create_message(owner, room, text: 'hello')
    service.update_message(owner, message, text: 'edited')
    service.react(member, message, '👍')
    service.unreact(member, message, '👍')
    service.delete_remote_message(owner, message)
    service.update_conversation(owner, room, title: 'Renamed')
    service.destroy_conversation(owner, room)

    expect(payloads(channel).pluck('type')).to eq(%w(message updated react unreact deleted roomUpdated roomDeleted))
    expect(payloads(channel)[1]['body']).to include('messageId' => mid(message), 'text' => 'edited', 'editedAt' => be_present)
    expect(payloads(channel)[2]['body']).to include('messageId' => mid(message), 'reaction' => '👍', 'user' => include('id' => mid(member)))
    expect(payloads(channel)[4]['body']).to eq(mid(message))
    expect(payloads(channel)[5]['body']).to include('roomId' => mid(room), 'name' => 'Renamed', 'isArchived' => false)
    expect(payloads(channel).last['body']).to be_nil
  end

  it 'does not publish content to invitees, former members, or remote accounts' do
    room = service.create_conversation(owner, type: :group, title: 'Room', account_ids: [member.id])
    remote = Fabricate(:account, domain: 'remote.test')
    room.memberships.create!(account: remote)
    [member, remote].each { |account| subscribe("chatRoom:#{account.id}:#{room.id}") }
    message = service.create_message(owner, room, text: 'members only')
    service.send(:broadcast_to, member, 'chat.message', message, REST::ChatMessageSerializer)

    expect(events.map(&:first).grep(/\Amisskey:/)).to be_empty
  end

  it 'looks nothing up for a viewer without a compatible client' do
    room = service.create_conversation(owner, type: :group, title: 'Room', account_ids: [member.id])
    message = service.create_message(owner, room, text: 'hello')
    payload = REST::ChatMessageSerializer.new(message).as_json

    queries = chat_queries { described_class.broadcast(redis, member, 'chat.message', payload) }

    expect(queries).to be_empty
  end

  it 'looks the message and its conversation up once for every member with a client' do
    third = Fabricate(:user).account
    room = service.create_conversation(owner, type: :group, title: 'Room')
    [member, third].each { |account| room.memberships.create!(account: account) }
    [owner, member, third].each { |account| subscribe("chatRoom:#{account.id}:#{room.id}") }
    message = service.create_message(owner, room, text: 'hello')
    payload = REST::ChatMessageSerializer.new(message).as_json
    events.clear
    described_class::Lookups.reset

    messages = chat_queries(/\ASELECT "chat_messages"\.\* FROM "chat_messages" WHERE "chat_messages"\."id" =/) do
      [owner, member, third].each { |account| described_class.broadcast(redis, account, 'chat.message', payload) }
    end

    expect(messages.size).to eq(1)
    expect(events.map(&:first)).to match_array([owner, member, third].map { |account| "misskey:chatRoom:#{account.id}:#{room.id}" })
  end

  it 'stops compatibility publication when either feature is disabled' do
    room = service.create_conversation(owner, type: :direct, account_ids: [member.id])
    subscribe("chatUser:#{member.id}:#{owner.id}")
    Setting.misskey_compat_enabled = false
    service.create_message(owner, room, text: 'disabled')

    expect(events.map(&:first).grep(/\Amisskey:/)).to be_empty
  end

  it 'publishes only after the enclosing transaction commits' do
    subscribe("chatUser:#{member.id}:#{owner.id}")
    ChatConversation.transaction do
      room = service.create_conversation(owner, type: :direct, account_ids: [member.id])
      service.create_message(owner, room, text: 'committed')

      expect(payloads("chatUser:#{member.id}:#{owner.id}")).to be_empty
    end

    expect(payloads("chatUser:#{member.id}:#{owner.id}").first.dig('body', 'text')).to eq('committed')
  end

  it 'does not publish a message from a rolled back transaction' do
    subscribe("chatUser:#{member.id}:#{owner.id}")
    ChatConversation.transaction do
      room = service.create_conversation(owner, type: :direct, account_ids: [member.id])
      service.create_message(owner, room, text: 'rolled back')
      raise ActiveRecord::Rollback
    end

    expect(payloads("chatUser:#{member.id}:#{owner.id}")).to be_empty
  end

  it 'delivers the deletion ID only to the author when a message is hidden' do
    Setting.chat_soft_delete_enabled = true
    room = service.create_conversation(owner, type: :direct, account_ids: [member.id])
    subscribe("chatUser:#{owner.id}:#{member.id}")
    subscribe("chatUser:#{member.id}:#{owner.id}")
    message = service.create_message(owner, room, text: 'hide this')
    events.clear

    service.delete_message(owner, message)
    service.send(:broadcast_to, owner, 'chat.message', message, REST::ChatMessageSerializer)

    expect(payloads("chatUser:#{owner.id}:#{member.id}")).to contain_exactly(include('type' => 'deleted', 'body' => mid(message)))
    expect(payloads("chatUser:#{member.id}:#{owner.id}")).to be_empty
  end
end
