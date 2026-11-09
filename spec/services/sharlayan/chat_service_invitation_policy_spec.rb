# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::ChatService do
  let(:service) { described_class.new }
  let(:sender) { Fabricate(:user).account }
  let(:recipient) { Fabricate(:user).account }

  before do
    Setting.chat_enabled = true
    Setting.chat_max_group_members = 50
    sender.update!(silenced_at: Time.current)
  end

  after do
    Setting.chat_enabled = false
  end

  it 'rejects inviting a nonfollower when creating a group, and allows it once they follow' do
    expect do
      service.create_conversation(sender, type: :group, title: 'Room', account_ids: [recipient.id])
    end.to raise_error(described_class::Forbidden)
      .and(not_change(ChatInvitation, :count))

    recipient.follow!(sender)

    room = service.create_conversation(sender, type: :group, title: 'Room', account_ids: [recipient.id])

    expect(room.invitations.pending.exists?(invitee_account: recipient)).to be(true)
  end
end
