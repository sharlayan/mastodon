# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::ChatService do
  subject(:service) { described_class.new }

  include_context 'with an open chat policy'

  let(:owner) { Fabricate(:user).account }
  let(:member) { Fabricate(:user).account }
  let(:remote) { Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/bob', inbox_url: 'https://remote.test/users/bob/inbox', can_chat: true, chat_scope: 'everyone') }
  let(:bystander) { Fabricate(:account, domain: 'other.test', uri: 'https://other.test/users/carol', inbox_url: 'https://other.test/users/carol/inbox') }
  let(:room) do
    ChatConversation.create!(conversation_type: :group, owner_account: owner, title: 'Room').tap do |record|
      record.update!(uri: "https://cb6e6126.ngrok.io/chat/rooms/#{record.id}")
      record.memberships.create!(account: owner, role: :owner)
      record.memberships.create!(account: member)
      record.memberships.create!(account: remote)
      record.memberships.create!(account: bystander)
    end
  end

  def delivered(type)
    ActivityPub::DeliveryWorker.jobs.filter_map do |job|
      payload = JSON.parse(job['args'][0])
      [job['args'][2], payload] if payload['type'] == type
    end
  end

  before do
    Setting.chat_enabled = true
    Setting.chat_federation_enabled = true
    ActivityPub::DeliveryWorker.jobs.clear
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_federation_enabled = false
  end

  describe 'when a remote member of a local room is suspended' do
    before do
      room
      remote.suspend!
      SuspendAccountService.new.call(remote)
    end

    it 'takes them out of the room, tells them and the other servers, and does not bring them back when the suspension ends' do
      removes = delivered('Remove')

      expect(room.memberships.exists?(account: remote)).to be(false)
      expect(removes.map(&:first)).to contain_exactly(remote.inbox_url, bystander.inbox_url)
      expect(removes.map { |_, payload| payload['object'] }.uniq).to eq([remote.uri])
      expect(removes.map { |_, payload| payload['actor'] }.uniq).to eq([ActivityPub::TagManager.instance.uri_for(owner)])

      stub_request(:get, /remote\.test/).to_return(status: 404)
      remote.unsuspend!
      UnsuspendAccountService.new.call(remote)

      expect(room.memberships.exists?(account: remote)).to be(false)
    end
  end

  it 'takes back a pending invitation when the invited remote account is suspended' do
    invitation = room.invitations.create!(inviter_account: owner, invitee_account: Fabricate(:account, domain: 'third.test', uri: 'https://third.test/users/dave', inbox_url: 'https://third.test/users/dave/inbox'))

    invitation.invitee_account.suspend!
    SuspendAccountService.new.call(invitation.invitee_account)

    expect(invitation.reload).to be_cancelled
    expect(delivered('Undo').map(&:first)).to eq(['https://third.test/users/dave/inbox'])
  end

  it 'keeps going when an invitation is settled while the suspension is processed' do
    suspended = Fabricate(:account, domain: 'third.test', uri: 'https://third.test/users/dave', inbox_url: 'https://third.test/users/dave/inbox')
    other_room = ChatConversation.create!(conversation_type: :group, owner_account: owner, title: 'Other').tap do |record|
      record.update!(uri: "https://cb6e6126.ngrok.io/chat/rooms/#{record.id}")
      record.memberships.create!(account: owner, role: :owner)
    end
    settled = room.invitations.create!(inviter_account: owner, invitee_account: suspended)
    remaining = other_room.invitations.create!(inviter_account: owner, invitee_account: suspended)
    chat = described_class.new
    allow(chat).to receive(:cancel_invitation).and_call_original
    allow(chat).to receive(:cancel_invitation).with(owner, settled).and_raise(described_class::Forbidden)
    suspended.suspend!

    chat.remove_suspended_account(suspended)

    expect(remaining.reload).to be_cancelled
  end

  it 'keeps going when a member already left the room while the suspension is processed' do
    other_room = ChatConversation.create!(conversation_type: :group, owner_account: owner, title: 'Other').tap do |record|
      record.update!(uri: "https://cb6e6126.ngrok.io/chat/rooms/#{record.id}")
      record.memberships.create!(account: owner, role: :owner)
      record.memberships.create!(account: remote)
    end
    room
    chat = described_class.new
    allow(chat).to receive(:kick).and_call_original
    allow(chat).to receive(:kick).with(owner, room, remote).and_raise(ActiveRecord::RecordNotFound)
    remote.suspend!

    chat.remove_suspended_account(remote)

    expect(other_room.memberships.exists?(account: remote)).to be(false)
  end

  it 'does not let a pending invitation be used once the suspension ends' do
    invitee = Fabricate(:account, domain: 'third.test', uri: 'https://third.test/users/dave', inbox_url: 'https://third.test/users/dave/inbox')
    room.invitations.create!(inviter_account: owner, invitee_account: invitee)
    invitee.suspend!
    SuspendAccountService.new.call(invitee)
    invitee.unsuspend!
    ActivityPub::DeliveryWorker.jobs.clear

    ActivityPub::Activity.factory({ 'type' => 'Accept', 'actor' => invitee.uri, 'object' => { 'type' => 'Invite', 'object' => room.uri } }, invitee).perform

    expect(room.memberships.exists?(account: invitee)).to be(false)
    expect(delivered('Remove').map(&:first)).to eq([invitee.inbox_url])
  end

  it 'leaves a room owned by another server to that server' do
    mirror = ChatConversation.create!(conversation_type: :group, owner_account: bystander, title: 'Mirror', uri: 'https://other.test/chat/rooms/1')
    mirror.memberships.create!(account: bystander, role: :owner)
    mirror.memberships.create!(account: remote)
    mirror.memberships.create!(account: member)

    remote.suspend!
    SuspendAccountService.new.call(remote)

    expect(mirror.memberships.exists?(account: remote)).to be(true)
    expect(delivered('Remove')).to be_empty
  end

  it 'keeps a direct conversation, so that the messages come back with the account' do
    conversation = service.create_conversation(member, type: :direct, account_ids: [remote.id])

    remote.suspend!
    SuspendAccountService.new.call(remote)

    expect(ChatConversation.exists?(conversation.id)).to be(true)
  end

  describe 'when a whole domain is suspended' do
    before do
      room
      DomainBlock.create!(domain: 'remote.test', severity: :suspend).tap { |block| BlockDomainService.new.call(block) }
    end

    it 'tells the other servers that its members are gone' do
      expect(room.memberships.exists?(account: remote)).to be(false)
      expect(delivered('Remove').map(&:first)).to include(bystander.inbox_url)
    end
  end

  describe 'sending to a suspended account' do
    let(:direct) { service.create_conversation(member, type: :direct, account_ids: [remote.id]) }

    before do
      direct
      remote.suspend!
    end

    it 'refuses a direct message and stores nothing, refuses to edit an earlier message, and refuses an invitation' do
      expect { service.create_message(member, direct, text: 'hello') }.to raise_error(described_class::Forbidden)

      expect(direct.messages).to be_empty
      expect(delivered('Create')).to be_empty

      message = direct.messages.create!(account: member, text: 'before')

      expect { service.update_message(member, message, text: 'after') }.to raise_error(described_class::Forbidden)
      expect(message.reload.text).to eq('before')
      expect { service.invite(owner, room, Fabricate(:account, domain: 'gone.test', suspended_at: Time.current)) }
        .to raise_error(described_class::Forbidden)
    end

    it 'still sends to the rest of a group' do
      room

      expect { service.create_message(owner, room, text: 'hello') }.to change(ChatMessage, :count).by(1)
      expect(delivered('Create').map(&:first)).to eq([bystander.inbox_url])
    end
  end

  describe 'a suspended author' do
    let(:direct) { service.create_conversation(member, type: :direct, account_ids: [remote.id]) }
    let!(:message) { direct.messages.create!(account: remote, text: 'before suspension', uri: 'https://remote.test/chat/messages/1') }

    before { direct.update!(last_message: message) }

    def conversation_json
      REST::ChatConversationSerializer.new(ChatConversation.find(direct.id), current_account: member).as_json
    end

    it 'has their messages hidden until the suspension ends' do
      remote.suspend!
      expect(direct.messages.visible_to(member)).to be_empty

      remote.unsuspend!
      expect(direct.messages.visible_to(member)).to contain_exactly(message)
    end

    it 'does not show as the last message of a conversation' do
      own = direct.messages.create!(account: member, text: 'mine')
      direct.update!(last_message: message)
      remote.suspend!

      expect(conversation_json[:last_message][:id]).to eq(own.id.to_s)
    end

    it 'does not leave a conversation unread, has their attachments closed to members, and keeps their messages out of an export' do
      media = Fabricate(:media_attachment, account: remote, status: nil, remote_url: 'https://remote.test/file.png')
      message.chat_message_media_attachments.create!(media_attachment: media)
      remote.suspend!
      io = StringIO.new
      Export.new(member).write_chat_json(io)

      expect(conversation_json[:last_message]).to be_nil
      expect(conversation_json[:unread]).to be(false)
      expect(MediaAttachmentPolicy.new(member, media).download?).to be(false)
      expect(JSON.parse(io.string).dig('chat_conversations', 0, 'messages')).to be_empty
    end
  end

  describe 'an invitation from a suspended owner' do
    let(:remote_room) do
      ChatConversation.create!(conversation_type: :group, owner_account: remote, title: 'Remote', uri: 'https://remote.test/chat/rooms/1').tap do |record|
        record.memberships.create!(account: remote, role: :owner)
      end
    end
    let!(:invitation) { remote_room.invitations.create!(inviter_account: remote, invitee_account: member) }

    before do
      remote.suspend!
      ActivityPub::DeliveryWorker.jobs.clear
    end

    it 'cannot be accepted, and sends nothing to them when rejected' do
      expect { service.accept_invitation(member, invitation) }.to raise_error(described_class::Forbidden)

      expect(invitation.reload).to be_pending
      expect(remote_room.memberships.exists?(account: member)).to be(false)
      expect(delivered('Accept')).to be_empty

      service.reject_invitation(member, invitation)

      expect(ChatInvitation.where(id: invitation.id, state: :pending)).to be_empty
      expect(delivered('Reject')).to be_empty
    end
  end

  describe 'an invitation from a server that is refused here' do
    let(:remote_room) do
      ChatConversation.create!(conversation_type: :group, owner_account: remote, title: 'Remote', uri: 'https://remote.test/chat/rooms/2').tap do |record|
        record.memberships.create!(account: remote, role: :owner)
      end
    end
    let!(:invitation) { remote_room.invitations.create!(inviter_account: remote, invitee_account: member) }

    before do
      DomainBlock.create!(domain: 'remote.test', severity: :suspend)
      ActivityPub::DeliveryWorker.jobs.clear
    end

    it 'cannot be accepted, even when the owner account is not marked as suspended' do
      expect(remote.reload).to_not be_suspended
      expect { service.accept_invitation(member, invitation) }.to raise_error(described_class::Forbidden)

      expect(invitation.reload).to be_pending
      expect(delivered('Accept')).to be_empty
    end

    it 'cannot be accepted from a server outside the list in limited federation mode' do
      DomainBlock.where(domain: 'remote.test').destroy_all
      allow(Rails.configuration.x.mastodon).to receive(:limited_federation_mode).and_return(true)

      expect { service.accept_invitation(member, invitation) }.to raise_error(described_class::Forbidden)
    end
  end

  describe 'a member blocking another in a group' do
    let(:message) { room.messages.create!(account: remote, text: 'hello', uri: 'https://remote.test/chat/messages/5') }

    before { room }

    it 'does not stop them sending to the group or still seeing their messages, nor reacting when both block each other' do
      owner.block!(remote)

      expect { service.create_message(owner, room, text: 'hello') }.to change(ChatMessage, :count).by(1)
      expect(service.receive_group_message(remote, room_uri: room.uri, uri: 'https://remote.test/chat/messages/6', text: 'hi')).to be_present
      expect(room.messages.visible_to(owner)).to include(message)

      remote.block!(owner)
      mine = room.messages.create!(account: owner, text: 'mine')

      expect(service.react(owner, message, '👍')).to be_present
      expect { service.react_remote(remote, mine, '👍', activity_id: 'https://remote.test/reactions/1') }.to change { mine.reactions.count }.by(1)
    end
  end

  describe 'an old invitation after the invitee domain was suspended and let back in' do
    let(:invitee) { Fabricate(:account, domain: 'blocked.test', uri: 'https://blocked.test/users/erin', inbox_url: 'https://blocked.test/users/erin/inbox') }

    before do
      room.invitations.create!(inviter_account: owner, invitee_account: invitee)
      block = DomainBlock.create!(domain: 'blocked.test', severity: :suspend)
      BlockDomainService.new.call(block)
      block.destroy!
      invitee.reload.unsuspend!
      ActivityPub::DeliveryWorker.jobs.clear
    end

    it 'is answered with a Remove, so that their server does not keep a room that is not there' do
      accept = {
        'type' => 'Accept',
        'actor' => invitee.uri,
        'object' => { 'type' => 'Invite', 'object' => room.uri },
      }

      ActivityPub::Activity.factory(accept, invitee).perform

      expect(room.memberships.exists?(account: invitee)).to be(false)
      expect(delivered('Remove').map(&:first)).to eq([invitee.inbox_url])
    end
  end
end
