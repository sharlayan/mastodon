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
      it 'delivers to followers and following inboxes' do
        expect_push_bulk_to_match(
          ActivityPub::DeliveryWorker,
          a_collection_containing_exactly(
            [json, account.id, 'http://follower.example.com/inbox', {}],
            [json, account.id, 'http://following.example.com/inbox', {}]
          )
        ) do
          subject.perform(json, account.id, '')
        end
      end

      it 'does not deliver to unrelated servers' do
        allow(Sidekiq::Client).to receive(:push_bulk)

        subject.perform(json, account.id, '')

        expect(Sidekiq::Client).to_not have_received(:push_bulk).with(
          hash_including('args' => a_collection_including(
            a_collection_including('http://unrelated.example.com/inbox')
          ))
        )
      end
    end

    context 'with a target inbox' do
      it 'delivers to followers, following, and target inboxes' do
        expect_push_bulk_to_match(
          ActivityPub::DeliveryWorker,
          a_collection_containing_exactly(
            [json, account.id, 'http://follower.example.com/inbox', {}],
            [json, account.id, 'http://following.example.com/inbox', {}],
            [json, account.id, 'http://target.example.com/inbox', {}]
          )
        ) do
          subject.perform(json, account.id, 'http://target.example.com/inbox')
        end
      end
    end

    context 'when target inbox overlaps with follower inbox' do
      it 'deduplicates inboxes' do
        expect_push_bulk_to_match(
          ActivityPub::DeliveryWorker,
          a_collection_containing_exactly(
            [json, account.id, 'http://follower.example.com/inbox', {}],
            [json, account.id, 'http://following.example.com/inbox', {}]
          )
        ) do
          subject.perform(json, account.id, 'http://follower.example.com/inbox')
        end
      end
    end

    context 'when account is not found' do
      it 'does not raise error' do
        expect { subject.perform(json, -1, '') }.to_not raise_error
      end
    end
  end
end
