# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ReactService, type: :service do
  subject { described_class.new }

  let(:sender) { Fabricate(:account, username: 'alice') }

  describe 'local' do
    let(:bob)    { Fabricate(:account) }
    let(:status) { Fabricate(:status, account: bob) }

    before do
      subject.call(sender, status, '👍')
    end

    it 'creates a reaction' do
      expect(status.reactions.first).to_not be_nil
    end

    it 'sends a local notification' do
      expect(LocalNotificationWorker).to have_enqueued_sidekiq_job(bob.id, anything, 'StatusReaction', 'reaction')
    end
  end

  describe 'remote ActivityPub' do
    let(:bob)    { Fabricate(:account, protocol: :activitypub, username: 'bob', domain: 'example.com', inbox_url: 'http://example.com/inbox') }
    let(:status) { Fabricate(:status, account: bob) }

    before do
      stub_request(:post, 'http://example.com/inbox').to_return(status: 200, body: '', headers: {})
      subject.call(sender, status, '👍')
    end

    it 'creates a reaction' do
      expect(status.reactions.first).to_not be_nil
    end

    it 'enqueues a ReactionsDistributionWorker' do
      expect(ActivityPub::ReactionsDistributionWorker).to have_enqueued_sidekiq_job(anything, sender.id, 'http://example.com/inbox')
    end
  end

  describe 'distribution to the reactor followers' do
    let(:status) { Fabricate(:status, account: sender) }

    before do
      subject.call(sender, status, '👍')
    end

    it 'enqueues ReactionsDistributionWorker with empty target for local status' do
      expect(ActivityPub::ReactionsDistributionWorker).to have_enqueued_sidekiq_job(anything, sender.id, '')
    end

    it 'enqueues BroadcastStatusUpdateWorker' do
      expect(BroadcastStatusUpdateWorker).to have_enqueued_sidekiq_job(status.id)
    end
  end

  describe 'idempotency' do
    let(:status) { Fabricate(:status) }

    it 'returns existing reaction without creating duplicate' do
      first  = subject.call(sender, status, '👍')
      second = subject.call(sender, status, '👍')
      expect(first.id).to eq second.id
      expect(StatusReaction.where(account: sender, status: status, name: '👍').count).to eq 1
    end
  end
end
