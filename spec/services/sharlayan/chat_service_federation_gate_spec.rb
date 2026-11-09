# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::ChatService do
  include_context 'with an open chat policy'

  let(:service) { described_class.new }
  let(:local) { Fabricate(:user).account }
  let(:remote_owner) do
    Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/owner', inbox_url: 'https://remote.test/users/owner/inbox', can_chat: true, chat_scope: 'everyone')
  end
  let(:remote_member) do
    Fabricate(:account, domain: 'other.test', uri: 'https://other.test/users/member', inbox_url: 'https://other.test/users/member/inbox', can_chat: true, chat_scope: 'everyone')
  end

  before do
    Setting.chat_enabled = true
    Setting.chat_federation_enabled = true
    local.user.settings[:chat_allow_group_invites] = true
    local.user.save!
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_federation_enabled = false
  end

  def receive_remote_invite(name)
    service.receive_invite(local, remote_owner, room_uri: "https://remote.test/chat/rooms/#{name}", title: 'Remote room')
  end

  context 'when chat federation is turned off' do
    it 'refuses to accept or reject an invitation to a room owned elsewhere' do
      invitation = receive_remote_invite('accept')
      Setting.chat_federation_enabled = false

      expect { service.accept_invitation(local, invitation) }.to raise_error(described_class::Error, 'Chat federation is disabled')
      expect { service.reject_invitation(local, invitation) }.to raise_error(described_class::Error, 'Chat federation is disabled')
      expect(invitation.reload).to be_pending
      expect(invitation.chat_conversation.memberships.exists?(account: local)).to be(false)
    end

    it 'refuses to leave a room owned elsewhere' do
      invitation = receive_remote_invite('leave')
      service.accept_invitation(local, invitation)
      Setting.chat_federation_enabled = false

      expect { service.leave(local, invitation.chat_conversation) }.to raise_error(described_class::Error, 'Chat federation is disabled')
      expect(invitation.chat_conversation.memberships.exists?(account: local)).to be(true)
    end

    it 'still lets a member leave a room owned here that has remote members' do
      owner = Fabricate(:user).account
      room = service.create_conversation(owner, type: :group, title: 'Room')
      room.memberships.create!(account: local)
      room.memberships.create!(account: remote_member)
      Setting.chat_federation_enabled = false

      service.leave(local, room)

      expect(room.memberships.exists?(account: local)).to be(false)
    end
  end
end
