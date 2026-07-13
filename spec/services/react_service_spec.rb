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

  describe 'distribution for a followers-only status' do
    let(:author) { Fabricate(:account) }
    let(:status) { Fabricate(:status, account: author, visibility: :private) }
    let(:authorized_follower) { Fabricate(:account, protocol: :activitypub, domain: 'authorized.example', inbox_url: 'https://authorized.example/inbox') }
    let(:reactor_follower) { Fabricate(:account, protocol: :activitypub, domain: 'reactor.example', inbox_url: 'https://reactor.example/inbox') }

    before do
      sender.follow!(author)
      authorized_follower.follow!(author)
      reactor_follower.follow!(sender)
      subject.call(sender, status, '👍')
    end

    it 'delivers only to the original status audience' do
      expect(ActivityPub::DeliveryWorker).to have_enqueued_sidekiq_job(anything, sender.id, authorized_follower.inbox_url)
      expect(ActivityPub::DeliveryWorker).to_not have_enqueued_sidekiq_job(anything, sender.id, reactor_follower.inbox_url)
      expect(ActivityPub::ReactionsDistributionWorker).to_not have_enqueued_sidekiq_job
    end
  end

  describe 'distribution for a remote followers-only status' do
    let(:author) { Fabricate(:account, protocol: :activitypub, domain: 'author.example', inbox_url: 'https://author.example/inbox') }
    let(:status) { Fabricate(:status, account: author, visibility: :private) }

    before do
      sender.follow!(author)
      subject.call(sender, status, '👍')
    end

    it 'delivers directly to the status author' do
      expect(ActivityPub::DeliveryWorker).to have_enqueued_sidekiq_job(anything, sender.id, author.inbox_url)
      expect(ActivityPub::ReactionsDistributionWorker).to_not have_enqueued_sidekiq_job
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
