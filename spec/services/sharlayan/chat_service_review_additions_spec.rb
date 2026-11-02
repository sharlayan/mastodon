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

  it 'rejects remote Add to an archived room' do
    conversation = service.create_conversation(local_account, type: :group, title: 'Room')
    service.archive(local_account, conversation, archived: true)

    expect do
      service.receive_add(local_account, room_uri: conversation.uri, account_uri: other_remote.uri)
    end.to raise_error(described_class::Error)
    expect(conversation.memberships.exists?(account: other_remote)).to be(false)
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

  it 'cleans up an ignored remote-only room' do
    invitation = service.receive_invite(local_account, remote_account, room_uri: 'https://remote.test/chat/rooms/ignored', title: 'Room')

    expect do
      ChatConversationCleanupWorker.new.perform(invitation.chat_conversation_id)
    end.to change(ChatConversation, :count).by(-1)
  end
end
