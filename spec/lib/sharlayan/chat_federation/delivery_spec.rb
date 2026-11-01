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

    expect(ActivityPub::DeliveryWorker).not_to have_received(:perform_async)
  end
end