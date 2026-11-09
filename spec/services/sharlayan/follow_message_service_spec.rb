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
    it 'stores a bounded snapshot of the followed message and ignores blank or non-string messages' do
      blank_follow = Fabricate(:follow, account: recipient)
      non_string_follow = Fabricate(:follow, account: recipient)

      service.store(follow, 'a' * 300)
      service.store(blank_follow, '')
      service.store(non_string_follow, ['Welcome'])

      expect(follow.reload.follow_message).to eq("#{'a' * 253}...")
      expect(blank_follow.reload.follow_message).to be_nil
      expect(non_string_follow.reload.follow_message).to be_nil
    end
  end

  describe '#notify' do
    before do
      follow.update_column(:follow_message, 'Welcome')
    end

    it 'enqueues a follow accepted notification only for a local recipient' do
      service.notify(follow, recipient: Fabricate(:remote_account))

      expect(LocalNotificationWorker).to_not have_received(:perform_async)

      service.notify(follow, recipient:)

      expect(LocalNotificationWorker).to have_received(:perform_async).with(recipient.id, follow.id, 'Follow', 'follow_accepted')
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
