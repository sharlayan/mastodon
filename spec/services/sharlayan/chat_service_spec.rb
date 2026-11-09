# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::ChatService do
  include_context 'with an open chat policy'

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
    Setting.chat_max_group_members = 50
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_federation_enabled = false
    Setting.chat_soft_delete_enabled = false
    Setting.chat_max_group_members = 50
  end

  describe 'invitation lifecycle' do
    let(:conversation) { service.create_conversation(local_account, type: :group, title: 'Room') }

    it 'allows a new invitation after a previous rejected, cancelled or accepted invitation' do
      invitation = service.invite(local_account, conversation, remote_account)

      %w(rejected cancelled accepted).each do |state|
        invitation.update!(state: state)
        new_invitation = service.invite(local_account, conversation, remote_account)

        expect(new_invitation).to be_pending, state
        expect(new_invitation.id).to_not eq(invitation.id), state
        invitation = new_invitation
      end
    end

    it 'rejects remote acceptance after the owner archives the room' do
      invitation = service.invite(local_account, conversation, remote_account)
      service.archive(local_account, conversation, archived: true)

      expect { service.receive_accept(remote_account, room_uri: conversation.uri) }.to raise_error(described_class::Error)
      expect(invitation.reload).to be_pending
      expect(conversation.accounts).to_not include(remote_account)
    end

    it 'rejects remote acceptance after the owner blocks the invitee' do
      service.invite(local_account, conversation, remote_account)
      local_account.block!(remote_account)

      expect { service.receive_accept(remote_account, room_uri: conversation.uri) }.to raise_error(described_class::Forbidden)
      expect(conversation.accounts).to_not include(remote_account)
    end

    it 'rejects remote acceptance when the group is already full' do
      service.invite(local_account, conversation, remote_account)
      Setting.chat_max_group_members = 1

      expect { service.receive_accept(remote_account, room_uri: conversation.uri) }.to raise_error(described_class::Error)
      expect(conversation.accounts).to_not include(remote_account)
    end
  end

  describe 'remote message lifecycle' do
    let(:conversation) do
      service.create_conversation(local_account, type: :group, title: 'Room').tap do |room|
        room.memberships.create!(account: remote_account)
      end
    end

    it 'rejects remote messages to archived groups' do
      service.archive(local_account, conversation, archived: true)
      expect do
        service.receive_group_message(remote_account, room_uri: conversation.uri, uri: 'https://remote.test/chat/messages/archived', text: 'blocked')
      end.to raise_error(described_class::Error)
      expect(conversation.messages).to be_empty
    end

    it 'rejects remote edits and reactions in archived groups' do
      message = service.receive_group_message(remote_account, room_uri: conversation.uri, uri: 'https://remote.test/chat/messages/edit', text: 'original')
      local_message = service.create_message(local_account, conversation, text: 'local')
      service.archive(local_account, conversation, archived: true)

      expect { service.update_remote_message(remote_account, message.reload, text: 'edited', edited_at: Time.current) }.to raise_error(described_class::Error)
      expect { service.react_remote(remote_account, local_message, '👍') }.to raise_error(described_class::Error)
      expect(message.reload.text).to eq('original')
      expect(local_message.reactions).to be_empty
    end

    it 'does not let a delayed remote edit replace newer content' do
      message = service.receive_group_message(remote_account, room_uri: conversation.uri, uri: 'https://remote.test/chat/messages/ordered', text: 'original')
      latest = Time.current.change(usec: 0)
      service.update_remote_message(remote_account, message, text: 'newer', edited_at: latest)
      service.update_remote_message(remote_account, message, text: 'older', edited_at: latest - 1.minute)

      expect(message.reload).to have_attributes(text: 'newer', edited_at: latest)
    end

    it 'rejects remote edits and reactions after a direct participant blocks the actor' do
      conversation = service.create_conversation(local_account, type: :direct, account_ids: [remote_account.id])
      remote_message = service.receive_direct_message(local_account, remote_account, uri: 'https://remote.test/chat/messages/blocked', text: 'original')
      local_message = service.create_message(local_account, conversation, text: 'local')
      local_account.block!(remote_account)

      expect { service.update_remote_message(remote_account, remote_message, text: 'blocked', edited_at: Time.current) }.to raise_error(described_class::Forbidden)
      expect { service.react_remote(remote_account, local_message, '👍') }.to raise_error(described_class::Forbidden)
      expect(remote_message.reload.text).to eq('original')
      expect(local_message.reactions).to be_empty
    end
  end

  describe 'media ownership' do
    let(:conversation) { service.create_conversation(local_account, type: :direct, account_ids: [remote_account.id]) }

    it 'rejects an attachment already referenced by a scheduled status, a status draft or a page' do
      %i(scheduled_status status_draft page).each do |usage|
        media = Fabricate(:media_attachment, account: local_account)
        if usage == :page
          Fabricate(:page, account: local_account, eye_catching_media_attachment: media)
        else
          media.update!(usage => Fabricate(usage, account: local_account))
        end

        expect { service.create_message(local_account, conversation, text: 'private', media_ids: [media.id]) }.to raise_error(described_class::Error), usage.to_s
      end
      expect(conversation.messages).to be_empty
    end
  end

  it 'stores local message and room URIs using the web domain' do
    allow(Rails.configuration.x).to receive(:web_domain).and_return('social.example.com')
    conversation = service.create_conversation(local_account, type: :group, title: 'Room')
    message = service.create_message(local_account, conversation, text: 'hello')

    expect(conversation.uri).to eq("https://social.example.com/chat/rooms/#{conversation.id}")
    expect(message.uri).to eq("https://social.example.com/chat/messages/#{message.id}")
  end

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

  describe 'remote conversations' do
    it 'creates a direct conversation with a remote account and delivers Create to the remote counterpart' do
      conversation = service.create_conversation(local_account, type: 'direct', account_ids: [remote_account.id])

      expect(conversation).to be_chat_direct
      expect(conversation.accounts).to contain_exactly(local_account, remote_account)
      expect { service.create_message(local_account, conversation, text: 'hi') }
        .to change(ActivityPub::DeliveryWorker.jobs, :size).by(1)
    end

    it 'does not federate a local-only hide' do
      other = Fabricate(:user).account
      conversation = service.create_conversation(local_account, type: :direct, account_ids: [other.id])
      message = service.create_message(local_account, conversation, text: 'hi')
      Setting.chat_soft_delete_enabled = true

      expect { service.delete_message(local_account, message) }.to_not change(ActivityPub::DeliveryWorker.jobs, :size)
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

    it 'federates deletion of a local room that has remote members' do
      conversation = service.create_conversation(local_account, type: :group, account_ids: [remote_account.id], title: 'Local room')
      conversation.memberships.create!(account: remote_account)

      expect { service.destroy_conversation(local_account, conversation) }
        .to change(ActivityPub::DeliveryWorker.jobs, :size).by(1)
      expect(ChatConversation.find_by(id: conversation.id)).to be_nil
    end

    it 'rejects a direct message the local recipient policy denies, but delivers a reply to a chat the recipient started' do
      local_account.user.settings[:chat_policy] = 'none'
      local_account.user.save!

      expect do
        service.receive_direct_message(local_account, remote_account, uri: 'https://remote.test/chat/messages/1', text: 'hi')
      end.to raise_error(Sharlayan::ChatService::Forbidden)

      conversation = service.create_conversation(local_account, type: :direct, account_ids: [remote_account.id])

      message = service.receive_direct_message(local_account, remote_account, uri: 'https://remote.test/chat/messages/reply', text: 'hi')

      expect(message.chat_conversation).to eq(conversation)
    end

    it 'still rejects messages in an existing chat once the recipient blocks the sender' do
      conversation = service.create_conversation(local_account, type: :direct, account_ids: [remote_account.id])
      local_account.block!(remote_account)

      expect do
        service.receive_direct_message(local_account, remote_account, uri: 'https://remote.test/chat/messages/blocked', text: 'hi')
      end.to raise_error(Sharlayan::ChatService::Forbidden)
      expect(conversation.messages).to be_empty
    end

    it 'rejects a new chat and an invitation from a domain the recipient blocks' do
      local_account.block_domain!(remote_account.domain)

      expect do
        service.receive_direct_message(local_account, remote_account, uri: 'https://remote.test/chat/messages/domain', text: 'hi')
      end.to raise_error(Sharlayan::ChatService::Forbidden)
      expect do
        service.receive_invite(local_account, remote_account, room_uri: 'https://remote.test/chat/rooms/domain', title: 'Room')
      end.to raise_error(Sharlayan::ChatService::Forbidden)
    end

    it 'gives the remote owner of a mirror room the owner role' do
      invitation = service.receive_invite(local_account, remote_account, room_uri: 'https://remote.test/chat/rooms/role', title: 'Room')

      expect(invitation.chat_conversation.memberships.find_by(account: remote_account)).to be_owner
    end

    it 'stores every attachment of an incoming message' do
      documents = %w(a b).map { |name| { 'url' => "https://remote.test/#{name}.jpg", 'mediaType' => 'image/jpeg' } }

      message = service.receive_direct_message(local_account, remote_account, uri: 'https://remote.test/chat/messages/multi', text: nil, attachments: documents)

      expect(message.media_attachments.map(&:remote_url)).to match_array(documents.pluck('url'))
    end

    it 'ignores incoming attachments with a non-HTTP URL' do
      document = { 'url' => 'javascript:alert(1)', 'mediaType' => 'image/jpeg' }

      expect do
        service.receive_direct_message(local_account, remote_account, uri: 'https://remote.test/chat/messages/script', text: 'hi', attachments: [document])
      end.to_not change(MediaAttachment, :count)
    end

    it 'relays a remote member leaving a local room to the other remote members' do
      other_member = Fabricate(:account, domain: 'other.test', uri: 'https://other.test/users/carol', inbox_url: 'https://other.test/users/carol/inbox')
      room = service.create_conversation(local_account, type: :group, title: 'Room')
      room.memberships.create!(account: remote_account)
      room.memberships.create!(account: other_member)
      ActivityPub::DeliveryWorker.clear

      service.receive_remove(remote_account, room_uri: room.uri, account_uri: remote_account.uri)

      expect(ActivityPub::DeliveryWorker.jobs.size).to eq(1)
      job = ActivityPub::DeliveryWorker.jobs.first
      expect(job['args'][2]).to eq(other_member.inbox_url)
      expect(JSON.parse(job['args'][0])).to include('type' => 'Remove', 'actor' => ActivityPub::TagManager.instance.uri_for(local_account), 'object' => remote_account.uri)
    end

    it 'does not relay departures from a room owned elsewhere' do
      conversation = service.receive_invite(local_account, remote_account, room_uri: 'https://remote.test/chat/rooms/relay', title: 'Room').chat_conversation
      other_member = Fabricate(:account, domain: 'other.test', uri: 'https://other.test/users/carol', inbox_url: 'https://other.test/users/carol/inbox')
      conversation.memberships.create!(account: other_member)
      ActivityPub::DeliveryWorker.clear

      expect { service.receive_remove(other_member, room_uri: conversation.uri, account_uri: other_member.uri) }
        .to_not change(ActivityPub::DeliveryWorker.jobs, :size)
    end

    it 'tells a local member that the remote owner removed them' do
      conversation = service.receive_invite(local_account, remote_account, room_uri: 'https://remote.test/chat/rooms/kick', title: 'Room').chat_conversation
      service.accept_invitation(local_account, conversation.invitations.find_by!(invitee_account: local_account))
      allow(service).to receive(:broadcast_to)

      service.receive_remove(remote_account, room_uri: conversation.uri, account_uri: ActivityPub::TagManager.instance.uri_for(local_account))

      expect(conversation.reload.accounts).to_not include(local_account)
      expect(service).to have_received(:broadcast_to).with(local_account, 'chat.conversation_delete', { conversation_id: conversation.id.to_s, reason: 'removed' })
    end

    it 'does not let a remote owner re-add a local account that left' do
      conversation = service.receive_invite(local_account, remote_account, room_uri: 'https://remote.test/chat/rooms/readd', title: 'Room').chat_conversation
      service.accept_invitation(local_account, conversation.invitations.find_by!(invitee_account: local_account))
      service.leave(local_account, conversation)

      expect do
        service.receive_add(remote_account, room_uri: conversation.uri, account_uri: ActivityPub::TagManager.instance.uri_for(local_account))
      end.to raise_error(Sharlayan::ChatService::Forbidden)
    end
  end

  describe 'archived rooms' do
    let(:room) { service.create_conversation(local_account, type: :group, title: 'Room').tap { |record| record.memberships.create!(account: remote_account) } }
    let!(:message) { service.receive_group_message(remote_account, room_uri: room.uri, uri: 'https://remote.test/chat/messages/before', text: 'before') }
    let!(:local_message) { service.create_message(local_account, room, text: 'local') }

    before do
      service.react_remote(remote_account, local_message, '👍')
      service.archive(local_account, room, archived: true)
    end

    it 'rejects a remote reaction undo but still lets a remote author delete a message' do
      expect { service.unreact_remote(remote_account, local_message, '👍') }.to raise_error(Sharlayan::ChatService::Error)
      expect(local_message.reactions.count).to eq(1)

      service.delete_remote_message(remote_account, message.reload)

      expect(message.reload).to be_deleted
    end
  end

  describe 'messages of former members' do
    let(:room) { service.create_conversation(local_account, type: :group, title: 'Room') }
    let!(:membership) { room.memberships.create!(account: remote_account) }
    let!(:message) { service.receive_group_message(remote_account, room_uri: room.uri, uri: 'https://remote.test/chat/messages/former', text: 'old') }

    before { membership.destroy! }

    it 'does not let the author edit them, but lets the author delete them' do
      expect { service.update_remote_message(remote_account, message.reload, text: 'new', edited_at: nil) }.to raise_error(Sharlayan::ChatService::Forbidden)
      expect(message.reload.text).to eq('old')

      service.delete_remote_message(remote_account, message.reload)

      expect(message.reload).to be_deleted
      expect(message.text).to be_nil
    end
  end

  it 'rejects media that is still being processed' do
    conversation = service.create_conversation(local_account, type: :group, title: 'Room')
    media = Fabricate(:media_attachment, account: local_account)
    media.update_column(:processing, :in_progress)

    expect { service.create_message(local_account, conversation, text: 'hi', media_ids: [media.id]) }
      .to raise_error(Sharlayan::ChatService::Error, /processed/)
  end

  describe 'room deletion' do
    it 'tells local members and pending invitees the room is gone' do
      member = Fabricate(:user).account
      invitee = Fabricate(:user).account
      room = service.create_conversation(local_account, type: :group, title: 'Room')
      service.accept_invitation(member, service.invite(local_account, room, member))
      service.invite(local_account, room, invitee)
      allow(service).to receive(:broadcast_to)

      service.destroy_conversation(local_account, room)

      expect(service).to have_received(:broadcast_to).with(local_account, 'chat.conversation_delete', { conversation_id: room.id.to_s })
      [member, invitee].each do |account|
        expect(service).to have_received(:broadcast_to).with(account, 'chat.conversation_delete', { conversation_id: room.id.to_s, reason: 'deleted' })
      end
    end
  end

  describe '#purge_account' do
    let(:friend) { Fabricate(:user).account }
    let(:room_owner) { Fabricate(:user).account }
    let!(:direct) { service.create_conversation(local_account, type: :direct, account_ids: [friend.id]) }
    let!(:owned_room) { service.create_conversation(local_account, type: :group, title: 'Owned', account_ids: [remote_account.id]) }
    let!(:joined_room) { service.create_conversation(room_owner, type: :group, title: 'Joined') }
    let!(:kept_message) { service.create_message(room_owner, joined_room, text: 'kept') }
    let!(:own_message) do
      service.accept_invitation(local_account, service.invite(room_owner, joined_room, local_account))
      service.create_message(local_account, joined_room, text: 'gone')
    end

    before do
      owned_room.memberships.create!(account: remote_account)
      joined_room.memberships.create!(account: remote_account)
      service.react(local_account, kept_message, '👍')
      ActivityPub::DeliveryWorker.clear
    end

    it 'removes the membership, messages and reactions but keeps other content, and tells remote members about the deleted room and the departure' do
      service.purge_account(local_account)

      expect(ChatConversation.where(id: [direct.id, owned_room.id])).to be_empty
      expect(joined_room.reload.accounts).to_not include(local_account)
      expect(ChatMessage.where(id: own_message.id)).to be_empty
      expect(kept_message.reload.reactions).to be_empty
      expect(joined_room.last_message).to eq(kept_message)
      expect(ActivityPub::DeliveryWorker.jobs.map { |job| JSON.parse(job['args'][0])['type'] }).to contain_exactly('Delete', 'Remove')
    end

    it 'does not federate when asked not to' do
      expect { service.purge_account(local_account, federate: false) }.to_not change(ActivityPub::DeliveryWorker.jobs, :size)
    end

    it 'never federates on behalf of a remote account' do
      expect { service.purge_account(remote_account) }.to_not change(ActivityPub::DeliveryWorker.jobs, :size)
      expect(joined_room.reload.accounts).to_not include(remote_account)
    end

    it 'runs when an account is deleted but its record is kept' do
      DeleteAccountService.new.call(local_account, reserve_username: true)

      expect(Account.where(id: local_account.id)).to exist
      expect(ChatMessage.where(id: own_message.id)).to be_empty
      expect(ChatConversation.where(id: owned_room.id)).to be_empty
    end
  end
end
