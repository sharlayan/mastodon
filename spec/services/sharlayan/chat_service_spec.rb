# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::ChatService do
  describe '#mark_read' do
    it 'broadcasts only when the read pointer advances' do
      account = Fabricate(:user).account
      other_account = Fabricate(:user).account
      conversation = described_class.new.create_conversation(account, type: :direct, account_ids: [other_account.id])
      message = described_class.new.create_message(other_account, conversation, text: 'hello')
      service = described_class.new
      allow(service).to receive(:broadcast_to)

      service.mark_read(account, conversation, message_id: message.id)
      service.mark_read(account, conversation, message_id: message.id)

      expect(service).to have_received(:broadcast_to).once
    end
  end
end

RSpec.describe Sharlayan::ChatService do
  let(:service) { described_class.new }
  let(:local_account) { Fabricate(:user).account }
  let(:remote_account) do
    Fabricate(:account,
              domain: 'remote.test',
              uri: 'https://remote.test/users/bob',
              inbox_url: 'https://remote.test/users/bob/inbox',
              can_chat: true,
              chat_scope: 'everyone')
  end

  before do
    Setting.chat_enabled = true
    Setting.chat_federation_enabled = true
    Setting.chat_soft_delete_enabled = false
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_federation_enabled = false
    Setting.chat_soft_delete_enabled = false
  end

  describe 'remote conversations' do
    it 'creates a direct conversation with a remote account' do
      conversation = service.create_conversation(local_account, type: 'direct', account_ids: [remote_account.id])

      expect(conversation).to be_chat_direct
      expect(conversation.accounts).to contain_exactly(local_account, remote_account)
    end

    it 'delivers Create to the remote counterpart' do
      conversation = service.create_conversation(local_account, type: 'direct', account_ids: [remote_account.id])

      expect { service.create_message(local_account, conversation, text: 'hi') }
        .to change(ActivityPub::DeliveryWorker.jobs, :size).by(1)
    end

    it 'does not federate a local-only hide' do
      other = Fabricate(:user).account
      conversation = service.create_conversation(local_account, type: :direct, account_ids: [other.id])
      message = service.create_message(local_account, conversation, text: 'hi')
      Setting.chat_soft_delete_enabled = true

      expect { service.delete_message(local_account, message) }.not_to change(ActivityPub::DeliveryWorker.jobs, :size)
      expect(message.reload.hidden_at).to be_present
      expect(message.reload.deleted_at).to be_nil
    end

    it 'creates a mirror group conversation from an invite and allows the invitee to accept' do
      remote_owner = Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/owner', inbox_url: 'https://remote.test/users/owner/inbox')
      invitation = service.receive_invite(local_account, remote_owner, room_uri: 'https://remote.test/chat/rooms/9', title: 'Remote room')

      conversation = invitation.chat_conversation
      expect(conversation).to be_chat_group
      expect(conversation.uri).to eq('https://remote.test/chat/rooms/9')
      expect(conversation.owner_account).to eq(remote_owner)

      expect { service.accept_invitation(local_account, invitation) }
        .to change(ActivityPub::DeliveryWorker.jobs, :size).by(1)
      expect(conversation.memberships.exists?(account: local_account)).to be(true)
    end

    it 'rejects a direct message when the local recipient policy denies it' do
      local_account.user.settings[:chat_policy] = 'none'
      local_account.user.save!

      expect do
        service.receive_direct_message(local_account, remote_account, uri: 'https://remote.test/chat/messages/1', text: 'hi')
      end.to raise_error(Sharlayan::ChatService::Forbidden)
    end
  end
end
