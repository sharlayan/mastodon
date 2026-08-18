# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UnreactService, type: :service do
  subject { described_class.new }

  let(:sender) { Fabricate(:account, username: 'alice') }

  describe 'local' do
    let(:bob)    { Fabricate(:account) }
    let(:status) { Fabricate(:status, account: bob) }

    before do
      sender.status_reactions.find_or_create_by!(status: status, name: '👍')
      subject.call(sender, status, '👍')
    end

    it 'removes a reaction' do
      expect(status.reactions.first).to be_nil
    end

    it 'enqueues BroadcastStatusUpdateWorker' do
      expect(BroadcastStatusUpdateWorker).to have_enqueued_sidekiq_job(status.id)
    end
  end

  describe 'remote ActivityPub' do
    let(:bob)    { Fabricate(:account, protocol: :activitypub, username: 'bob', domain: 'example.com', inbox_url: 'http://example.com/inbox') }
    let(:status) { Fabricate(:status, account: bob) }

    before do
      sender.status_reactions.find_or_create_by!(status: status, name: '👍')
      stub_request(:post, 'http://example.com/inbox').to_return(status: 200, body: '', headers: {})
      subject.call(sender, status, '👍')
    end

    it 'removes a reaction' do
      expect(status.reactions.first).to be_nil
    end

    it 'enqueues ReactionsDistributionWorker with target inbox' do
      expect(ActivityPub::ReactionsDistributionWorker).to have_enqueued_sidekiq_job(anything, sender.id, 'http://example.com/inbox')
    end
  end

  describe 'when reaction does not exist' do
    let(:status) { Fabricate(:status) }

    it 'raises RecordNotFound' do
      expect { subject.call(sender, status, '👍') }
        .to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe 'distribution' do
    let(:status) { Fabricate(:status, account: sender) }

    before do
      sender.status_reactions.find_or_create_by!(status: status, name: '👍')
      subject.call(sender, status, '👍')
    end

    it 'enqueues ReactionsDistributionWorker with empty target for local status' do
      expect(ActivityPub::ReactionsDistributionWorker).to have_enqueued_sidekiq_job(anything, sender.id, '')
    end
  end

  describe 'distribution for a followers-only status' do
    let(:author) { Fabricate(:account) }
    let(:status) { Fabricate(:status, account: author, visibility: :private) }
    let(:authorized_follower) { Fabricate(:account, protocol: :activitypub, domain: 'authorized.example', inbox_url: 'https://authorized.example/inbox') }
    let(:reactor_follower) { Fabricate(:account, protocol: :activitypub, domain: 'reactor.example', inbox_url: 'https://reactor.example/inbox') }

    before do
      authorized_follower.follow!(author)
      reactor_follower.follow!(sender)
      sender.status_reactions.create!(status: status, name: '👍')
      subject.call(sender, status, '👍')
    end

    it 'delivers only to the original status audience' do
      expect(ActivityPub::DeliveryWorker).to have_enqueued_sidekiq_job(anything, sender.id, authorized_follower.inbox_url)
      expect(ActivityPub::DeliveryWorker).to_not have_enqueued_sidekiq_job(anything, sender.id, reactor_follower.inbox_url)
      expect(ActivityPub::ReactionsDistributionWorker).to_not have_enqueued_sidekiq_job
    end
  end
end
