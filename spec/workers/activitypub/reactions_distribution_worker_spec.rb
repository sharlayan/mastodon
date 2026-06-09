# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityPub::ReactionsDistributionWorker do
  subject { described_class.new }

  let(:account)  { Fabricate(:account) }
  let(:follower) { Fabricate(:account, protocol: :activitypub, inbox_url: 'http://follower.example.com/inbox', domain: 'follower.example.com') }
  let(:following_account) { Fabricate(:account, protocol: :activitypub, inbox_url: 'http://following.example.com/inbox', domain: 'following.example.com') }
  let(:unrelated) { Fabricate(:account, protocol: :activitypub, inbox_url: 'http://unrelated.example.com/inbox', domain: 'unrelated.example.com') }
  let(:json) { '{"type":"Like","content":"👍"}' }

  describe '#perform' do
    before do
      follower.follow!(account)
      account.follow!(following_account)
    end

    context 'with empty target_inbox_url' do
      it 'delivers to follower and following inboxes (Misskey-style propagation)' do
        subject.perform(json, account.id, '')

        expect(ActivityPub::DeliveryWorker)
          .to have_enqueued_sidekiq_job(json, account.id, 'http://follower.example.com/inbox', anything)
          .and have_enqueued_sidekiq_job(json, account.id, 'http://following.example.com/inbox', anything)
      end

      it 'does not deliver to unrelated servers' do
        subject.perform(json, account.id, '')

        expect(ActivityPub::DeliveryWorker)
          .to_not have_enqueued_sidekiq_job(json, account.id, 'http://unrelated.example.com/inbox', anything)
      end
    end

    context 'with a target inbox' do
      it 'delivers to follower, following, and target inboxes' do
        subject.perform(json, account.id, 'http://target.example.com/inbox')

        expect(ActivityPub::DeliveryWorker)
          .to have_enqueued_sidekiq_job(json, account.id, 'http://follower.example.com/inbox', anything)
          .and have_enqueued_sidekiq_job(json, account.id, 'http://following.example.com/inbox', anything)
          .and have_enqueued_sidekiq_job(json, account.id, 'http://target.example.com/inbox', anything)
      end
    end

    context 'when target inbox overlaps with follower inbox' do
      it 'deduplicates inboxes' do
        subject.perform(json, account.id, 'http://follower.example.com/inbox')

        expect(ActivityPub::DeliveryWorker)
          .to have_enqueued_sidekiq_job(json, account.id, 'http://follower.example.com/inbox', anything)
          .exactly(1).time
      end
    end

    context 'when account is not found' do
      it 'does not raise error' do
        expect { subject.perform(json, -1, '') }.to_not raise_error
      end
    end
  end
end
