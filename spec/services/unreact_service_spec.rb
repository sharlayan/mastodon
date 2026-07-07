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
end
