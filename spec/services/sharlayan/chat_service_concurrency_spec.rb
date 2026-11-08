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
end
