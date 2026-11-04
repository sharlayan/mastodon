# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::ChatService do
  let(:service) { described_class.new }
  let(:local_account) { Fabricate(:user).account }
  let(:remote_account) do
    Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/review', inbox_url: 'https://remote.test/users/review/inbox')
  end
  let(:other_remote) do
    Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/other', inbox_url: 'https://remote.test/users/other/inbox')
  end

  before do
    Setting.chat_enabled = true
    Setting.chat_federation_enabled = true
    Setting.chat_soft_delete_enabled = false
    Setting.chat_max_group_members = 50
    Setting.chat_max_attachments = 4
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_federation_enabled = false
    Setting.chat_soft_delete_enabled = false
    Setting.chat_max_group_members = 50
    Setting.chat_max_attachments = 1
  end

  it 'hides a deleted message from its sender with remote members present' do
    conversation = service.create_conversation(local_account, type: :group, title: 'Room')
    conversation.memberships.create!(account: remote_account)
    message = service.create_message(local_account, conversation, text: 'retain me')
    Setting.chat_soft_delete_enabled = true

    service.delete_message(local_account, message)

    expect(message.reload).to have_attributes(text: 'retain me', deleted_at: nil, hidden_at: be_present)
  end

  it 'records a remote Add that an archive overtook' do
    conversation = service.create_conversation(local_account, type: :group, title: 'Room')
    service.archive(local_account, conversation, archived: true)

    service.receive_add(local_account, room_uri: conversation.uri, account_uri: other_remote.uri)

    expect(conversation.memberships.exists?(account: other_remote)).to be(true)
  end

  it 'enforces group capacity for remote Add' do
    conversation = service.create_conversation(local_account, type: :group, title: 'Room')
    conversation.memberships.create!(account: remote_account)
    Setting.chat_max_group_members = 2

    expect do
      service.receive_add(local_account, room_uri: conversation.uri, account_uri: other_remote.uri)
    end.to raise_error(described_class::Error)
    expect(conversation.memberships.exists?(account: other_remote)).to be(false)
  end

  it 'does not leave an empty direct conversation after an invalid message' do
    expect do
      service.receive_direct_message(local_account, remote_account, uri: 'https://remote.test/chat/messages/invalid-review', text: 'a' * 4_097)
    end.to raise_error(ActiveRecord::RecordInvalid)

    expect(ChatConversation.exists?(direct_key: [local_account.id, remote_account.id].sort.join(':'))).to be(false)
  end

  describe 'a remote Remove' do
    let(:outsider) do
      Fabricate(:account, domain: 'outsider.test', uri: 'https://outsider.test/users/mallory', inbox_url: 'https://outsider.test/users/mallory/inbox')
    end

    it 'is not announced or relayed when the actor removing itself is not in the room' do
      conversation = service.create_conversation(local_account, type: :group, title: 'Room')
      conversation.memberships.create!(account: remote_account)
      ActivityPub::DeliveryWorker.clear
      allow(service).to receive(:broadcast)

      service.receive_remove(outsider, room_uri: conversation.uri, account_uri: outsider.uri)

      expect(service).to_not have_received(:broadcast)
      expect(ActivityPub::DeliveryWorker.jobs).to be_empty
    end

    it 'still finishes when the owner removes an account that is already gone' do
      conversation = service.receive_invite(local_account, remote_account, room_uri: 'https://remote.test/chat/rooms/retried', title: 'Room').chat_conversation
      service.accept_invitation(local_account, conversation.invitations.find_by!(invitee_account: local_account))
      allow(service).to receive(:broadcast)

      service.receive_remove(remote_account, room_uri: conversation.uri, account_uri: outsider.uri)

      expect(service).to have_received(:broadcast).with(conversation, 'chat.member_leave', { conversation_id: conversation.id.to_s, account_id: outsider.id.to_s })
    end

    it 'tells local members when the remote owner removes itself and the room goes away' do
      conversation = service.receive_invite(local_account, remote_account, room_uri: 'https://remote.test/chat/rooms/gone', title: 'Room').chat_conversation
      service.accept_invitation(local_account, conversation.invitations.find_by!(invitee_account: local_account))
      allow(service).to receive(:broadcast_to)

      service.receive_remove(remote_account, room_uri: conversation.uri, account_uri: remote_account.uri)

      expect(ChatConversation.exists?(conversation.id)).to be(false)
      expect(service).to have_received(:broadcast_to).with(local_account, 'chat.conversation_delete', { conversation_id: conversation.id.to_s })
    end
  end

  it 'streams message times in the same format as the REST API' do
    conversation = service.create_conversation(local_account, type: :group, title: 'Room')
    events = []
    allow(service.redis).to receive(:publish) { |_channel, event| events << JSON.parse(event) }

    message = service.create_message(local_account, conversation, text: 'hello')

    payload = JSON.parse(events.find { |event| event['event'] == 'chat.message' }.fetch('payload'))
    expect(payload['created_at']).to eq(message.created_at.as_json).and match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\z/)
  end

  it 'cleans up an ignored remote-only room' do
    invitation = service.receive_invite(local_account, remote_account, room_uri: 'https://remote.test/chat/rooms/ignored', title: 'Room')

    travel_to((ChatConversationCleanupWorker::CLEANUP_DELAY + 1.day).from_now) do
      expect do
        ChatConversationCleanupWorker.new.perform(invitation.chat_conversation_id)
      end.to change(ChatConversation, :count).by(-1)
    end
  end
end
