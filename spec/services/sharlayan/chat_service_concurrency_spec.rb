# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::ChatService do
  include_context 'with an open chat policy'

  let(:service) { described_class.new }
  let(:owner) { Fabricate(:user).account }
  let(:invitee) { Fabricate(:user).account }
  let(:room) { service.create_conversation(owner, type: :group, title: 'Room') }

  before do
    Setting.chat_enabled = true
    invitee.user.settings[:chat_allow_group_invites] = true
    invitee.user.save!
  end

  after { Setting.chat_enabled = false }

  describe 'answering an invitation that was accepted meanwhile' do
    let!(:invitation) { service.invite(owner, room, invitee) }
    let(:stale_invitation) { ChatInvitation.find(invitation.id) }

    before do
      stale_invitation
      service.accept_invitation(invitee, ChatInvitation.find(invitation.id))
    end

    it 'does not let a cancellation overwrite the acceptance' do
      expect { service.cancel_invitation(owner, stale_invitation) }.to raise_error(described_class::Forbidden)

      expect(invitation.reload).to be_accepted
      expect(room.memberships.exists?(account: invitee)).to be(true)
    end

    it 'does not let a rejection overwrite the acceptance' do
      expect { service.reject_invitation(invitee, stale_invitation) }.to raise_error(described_class::Forbidden)

      expect(invitation.reload).to be_accepted
      expect(room.memberships.exists?(account: invitee)).to be(true)
    end
  end

  describe 'sending to a room archived meanwhile' do
    it 'refuses the message' do
      stale_room = ChatConversation.find(room.id)
      ChatConversation.find(room.id).update!(archived_at: Time.current)

      expect { service.create_message(owner, stale_room, text: 'late') }.to raise_error(described_class::Error, 'Archived conversations are read-only')
      expect(room.messages.count).to eq(0)
    end
  end

  describe 'marking a room as read' do
    let(:earlier) { service.create_message(invitee, room, text: 'first') }
    let(:later) { service.create_message(invitee, room, text: 'second') }

    before { room.memberships.create!(account: invitee) }

    it 'does not move the pointer back when a newer read was saved meanwhile' do
      stale_membership = room.memberships.find_by!(account: owner)
      earlier
      service.mark_read(owner, room, message_id: later.id)
      allow(service).to receive(:membership!).and_return(stale_membership)

      membership = service.mark_read(owner, room, message_id: earlier.id)

      expect(room.memberships.find_by!(account: owner).last_read_message_id).to eq(later.id)
      expect(membership.last_read_message_id).to eq(later.id)
    end

    it 'moves the pointer forward' do
      earlier
      later

      membership = service.mark_read(owner, room)

      expect(membership.last_read_message_id).to eq(later.id)
      expect(room.memberships.find_by!(account: owner).last_read_message_id).to eq(later.id)
    end

    it 'keeps a newer pointer when the sender writes again' do
      sent = service.create_message(owner, room, text: 'mine')
      newer = room.messages.create!(id: sent.id + 1000, account: invitee, text: 'arrived out of order')
      room.memberships.find_by!(account: owner).update!(last_read_message: newer)
      stale_membership = room.memberships.find_by!(account: owner).tap { |membership| membership.last_read_message_id = sent.id }
      allow(service).to receive(:membership!).and_return(stale_membership)

      service.create_message(owner, room, text: 'again')

      expect(room.memberships.find_by!(account: owner).last_read_message_id).to eq(newer.id)
    end
  end
end
