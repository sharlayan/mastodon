# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::FollowMessageService do
  subject(:service) { described_class.new }

  let(:recipient) { Fabricate(:account) }
  let(:follow) { Fabricate(:follow, account: recipient) }

  before do
    allow(LocalNotificationWorker).to receive(:perform_async)
  end

  describe '#store' do
    it 'stores a bounded snapshot of the followed message' do
      service.store(follow, 'a' * 300)

      expect(follow.reload.follow_message).to eq("#{'a' * 253}...")
    end

    it 'leaves the follow unchanged for a blank message' do
      service.store(follow, '')

      expect(follow.reload.follow_message).to be_nil
    end
  end

  describe '#notify' do
    before do
      follow.update_column(:follow_message, 'Welcome')
    end

    it 'enqueues a follow accepted notification for a local recipient' do
      service.notify(follow, recipient:)

      expect(LocalNotificationWorker).to have_received(:perform_async).with(recipient.id, follow.id, 'Follow', 'follow_accepted')
    end

    it 'does not enqueue a notification for a remote recipient' do
      remote_recipient = Fabricate(:remote_account)

      service.notify(follow, recipient: remote_recipient)

      expect(LocalNotificationWorker).to_not have_received(:perform_async)
    end
  end

  describe '#call_for_request' do
    it 'finds the authorized follow and delivers the remote message' do
      request = instance_double(FollowRequest, account: recipient, target_account: follow.target_account)

      service.call_for_request(request, 'Remote welcome')

      expect(follow.reload.follow_message).to eq('Remote welcome')
      expect(LocalNotificationWorker).to have_received(:perform_async).with(recipient.id, follow.id, 'Follow', 'follow_accepted')
    end
  end
end
