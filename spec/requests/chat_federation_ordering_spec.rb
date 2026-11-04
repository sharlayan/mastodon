# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Chat federation message ordering' do
  let(:service) { Sharlayan::ChatService.new }
  let(:owner) { Fabricate(:user).account }
  let(:remote) { Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/bob', inbox_url: 'https://remote.test/users/bob/inbox', can_chat: true, chat_scope: 'everyone') }
  let(:message_uri) { 'https://remote.test/chat/messages/ordering' }

  before do
    Setting.chat_enabled = true
    Setting.chat_federation_enabled = true
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_federation_enabled = false
  end

  def perform(type, text, updated: nil, room: nil)
    object = {
      'id' => message_uri, 'type' => 'Note', 'attributedTo' => remote.uri,
      '_misskey_talk' => true, '_misskey_content' => text,
      'to' => [ActivityPub::TagManager.instance.uri_for(owner)],
      'published' => '2026-11-03T00:00:00.000Z'
    }
    object['updated'] = updated if updated
    object['_misskey_chatRoom'] = room.uri if room
    ActivityPub::Activity.factory({ 'type' => type, 'actor' => remote.uri, 'object' => object }, remote, delivered_to_account_id: owner.id).perform
  end

  [false, true].each do |group|
    it "preserves the latest #{group ? 'group' : 'direct'} edit when updates precede creation" do
      if group
        room = service.create_conversation(owner, type: :group, title: 'Room')
        room.memberships.create!(account: remote)
      end

      perform('Update', 'latest', updated: '2026-11-03T00:00:02.002Z', room: room)
      perform('Update', 'older', updated: '2026-11-03T00:00:01.001Z', room: room)
      perform('Create', 'original', room: room)

      message = ChatMessage.find_by!(uri: message_uri)
      expect(message.text).to eq('latest')
      expect(message.edited_at).to eq(Time.iso8601('2026-11-03T00:00:02.002Z'))
      expect(ChatMessage.where(uri: message_uri).count).to eq(1)
    end
  end

  it 'clears a remote caption while retaining its attachment' do
    message = service.receive_direct_message(owner, remote, uri: message_uri, text: 'caption')
    attachment = Fabricate(:media_attachment, account: remote)
    message.chat_message_media_attachments.create!(media_attachment: attachment)

    perform('Update', '', updated: '2026-11-03T00:00:01.001Z')

    expect(message.reload.text).to be_nil
    expect(message.media_attachments).to contain_exactly(attachment)
    expect(message.edited_at).to be_present
  end

  it 'keeps text when an empty update would leave the message without content' do
    message = service.receive_direct_message(owner, remote, uri: message_uri, text: 'original')

    perform('Update', '', updated: '2026-11-03T00:00:01.001Z')

    expect(message.reload.text).to eq('original')
    expect(message.edited_at).to be_nil
  end

  it 'applies an update when a concurrent Create wins after the initial lookup' do
    message = service.receive_direct_message(owner, remote, uri: message_uri, text: 'original')
    allow(ChatMessage).to receive(:find_by).and_call_original
    allow(ChatMessage).to receive(:find_by).with(uri: message_uri).and_return(nil, message)

    perform('Update', 'latest', updated: '2026-11-03T00:00:02.002Z')

    expect(message.reload.text).to eq('latest')
    expect(message.edited_at).to eq(Time.iso8601('2026-11-03T00:00:02.002Z'))
  end

  it 'assigns increasing millisecond versions to simultaneous local edits from separate requests' do
    conversation = service.create_conversation(owner, type: :direct, account_ids: [remote.id])
    message = service.create_message(owner, conversation, text: 'original')
    stale_copy = ChatMessage.find(message.id)
    versions = []

    freeze_time do
      service.update_message(owner, message, text: 'first')
      versions << Sharlayan::ChatFederation::Payload.update(message).dig('object', 'updated')
      service.update_message(owner, stale_copy, text: 'second')
      versions << Sharlayan::ChatFederation::Payload.update(stale_copy).dig('object', 'updated')
    end

    expect(Time.iso8601(versions.last) - Time.iso8601(versions.first)).to be >= 0.001
    expect(message.reload.text).to eq('second')
  end

  it 'retries a group message that overtakes its acceptance without adding the sender itself' do
    room = service.create_conversation(owner, type: :group, title: 'Room')
    service.invite(owner, room, remote)

    expect { perform('Create', 'first message', room: room) }.to raise_error(StandardError, /Waiting for chat membership/)
    expect(room.memberships.exists?(account: remote)).to be(false)
    expect(ChatMessage.exists?(uri: message_uri)).to be(false)

    service.receive_accept(remote, room_uri: room.uri)
    2.times { perform('Create', 'first message', room: room) }

    expect(room.messages.where(uri: message_uri).count).to eq(1)
  end

  it 'retries a remote group message until the room invitation arrives and is accepted' do
    room_uri = 'https://remote.test/chat/rooms/ordering'
    room_reference = instance_double(ChatConversation, uri: room_uri)

    expect { perform('Create', 'first message', room: room_reference) }.to raise_error(StandardError, /Waiting for chat room/)

    invitation = service.receive_invite(owner, remote, room_uri: room_uri, title: 'Remote room')
    expect { perform('Create', 'first message', room: room_reference) }.to raise_error(StandardError, /Waiting for chat membership/)
    expect(ChatMessage.exists?(uri: message_uri)).to be(false)

    service.accept_invitation(owner, invitation)
    perform('Create', 'first message', room: room_reference)

    expect(invitation.chat_conversation.messages.find_by!(uri: message_uri).text).to eq('first message')
  end
end
