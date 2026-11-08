# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::ChatFederation::Delivery do
  let(:owner) { Fabricate(:account) }
  let(:remote) { Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/bob', inbox_url: 'https://remote.test/users/bob/inbox') }
  let(:conversation) do
    ChatConversation.create!(conversation_type: :group, owner_account: owner, title: 'Room').tap do |record|
      record.memberships.create!(account: owner, role: :owner)
      record.memberships.create!(account: remote)
    end
  end

  it 'delivers once per remote inbox and skips local accounts' do
    allow(ActivityPub::DeliveryWorker).to receive(:perform_async)

    described_class.call(actor: owner, conversation: conversation, payload: { type: 'Update' })

    expect(ActivityPub::DeliveryWorker).to have_received(:perform_async).once
    expect(ActivityPub::DeliveryWorker).to have_received(:perform_async).with(anything, owner.id, remote.inbox_url)
  end

  it 'skips the excluded account' do
    allow(ActivityPub::DeliveryWorker).to receive(:perform_async)

    described_class.call(actor: owner, conversation: conversation, payload: { type: 'Update' }, except_account_id: remote.id)

    expect(ActivityPub::DeliveryWorker).to_not have_received(:perform_async)
  end

  context 'when a remote member is suspended' do
    before do
      conversation
      remote.suspend!
      allow(ActivityPub::DeliveryWorker).to receive(:perform_async)
    end

    %w(Create Update Announce EmojiReact Add).each do |type|
      it "does not send them #{type}" do
        described_class.call(actor: owner, conversation: conversation, payload: { 'type' => type })

        expect(ActivityPub::DeliveryWorker).to_not have_received(:perform_async)
      end
    end

    %w(Delete Remove Undo).each do |type|
      it "still sends them #{type}" do
        described_class.call(actor: owner, conversation: conversation, payload: { 'type' => type })

        expect(ActivityPub::DeliveryWorker).to have_received(:perform_async).with(anything, owner.id, remote.inbox_url)
      end
    end

    it 'does not send a suspended pending invitee a room Update' do
      invitee = Fabricate(:account, domain: 'other.test', uri: 'https://other.test/users/carol', inbox_url: 'https://other.test/users/carol/inbox')
      conversation.invitations.create!(inviter_account: owner, invitee_account: invitee)
      invitee.suspend!

      described_class.call(actor: owner, conversation: conversation, payload: { 'type' => 'Update' }, include_pending_invitees: true)

      expect(ActivityPub::DeliveryWorker).to_not have_received(:perform_async)
    end
  end
end
