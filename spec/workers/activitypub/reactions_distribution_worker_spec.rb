# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityPub::ReactionsDistributionWorker do
  subject { described_class.new }

  let(:reactor)        { Fabricate(:account) }
  let(:status_author)  { Fabricate(:account) }
  let(:author_follower) { Fabricate(:account, protocol: :activitypub, inbox_url: 'http://follower.example.com/inbox', domain: 'follower.example.com') }
  let(:reactor_follower) { Fabricate(:account, protocol: :activitypub, inbox_url: 'http://reactor-follower.example.com/inbox', domain: 'reactor-follower.example.com') }
  let(:unrelated) { Fabricate(:account, protocol: :activitypub, inbox_url: 'http://unrelated.example.com/inbox', domain: 'unrelated.example.com') }
  let(:json) { '{"type":"Like","content":"👍"}' }

  describe '#perform' do
    before do
      author_follower.follow!(status_author)
      reactor_follower.follow!(reactor)
    end

    context 'with empty target_inbox_url' do
      it 'delivers to the status author followers servers, signed by the reactor' do
        subject.perform(json, reactor.id, '', status_author.id)

        expect(ActivityPub::DeliveryWorker)
          .to have_enqueued_sidekiq_job(json, reactor.id, 'http://follower.example.com/inbox', anything)
      end

      it 'does not deliver to the reactor own followers' do
        subject.perform(json, reactor.id, '', status_author.id)

        expect(ActivityPub::DeliveryWorker)
          .to_not have_enqueued_sidekiq_job(json, reactor.id, 'http://reactor-follower.example.com/inbox', anything)
      end

      it 'does not deliver to unrelated servers' do
        subject.perform(json, reactor.id, '', status_author.id)

        expect(ActivityPub::DeliveryWorker)
          .to_not have_enqueued_sidekiq_job(json, reactor.id, 'http://unrelated.example.com/inbox', anything)
      end
    end

    context 'with a target inbox' do
      it 'delivers to the status author followers and the target inbox' do
        subject.perform(json, reactor.id, 'http://target.example.com/inbox', status_author.id)

        expect(ActivityPub::DeliveryWorker)
          .to have_enqueued_sidekiq_job(json, reactor.id, 'http://follower.example.com/inbox', anything)
          .and have_enqueued_sidekiq_job(json, reactor.id, 'http://target.example.com/inbox', anything)
      end
    end

    context 'when target inbox overlaps with an author follower inbox' do
      it 'deduplicates inboxes' do
        subject.perform(json, reactor.id, 'http://follower.example.com/inbox', status_author.id)

        expect(ActivityPub::DeliveryWorker)
          .to have_enqueued_sidekiq_job(json, reactor.id, 'http://follower.example.com/inbox', anything)
          .exactly(1).time
      end
    end

    context 'when status_account_id is omitted' do
      it 'falls back to the reactor own followers' do
        subject.perform(json, reactor.id, '')

        expect(ActivityPub::DeliveryWorker)
          .to have_enqueued_sidekiq_job(json, reactor.id, 'http://reactor-follower.example.com/inbox', anything)
      end
    end

    context 'when account is not found' do
      it 'does not raise error' do
        expect { subject.perform(json, -1, '') }.to_not raise_error
      end
    end
  end
end
