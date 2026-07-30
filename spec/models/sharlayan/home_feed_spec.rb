# frozen_string_literal: true

require 'rails_helper'

RSpec.describe HomeFeed do
  subject { described_class.new(account) }

  let(:account) { Fabricate(:account) }
  let(:followed) { Fabricate(:account) }
  let(:other) { Fabricate(:account) }

  describe '#get' do
    before do
      account.follow!(followed)

      Fabricate(:status, account: account,  id: 1)
      Fabricate(:status, account: account,  id: 2)
      status = Fabricate(:status, account: followed, id: 3)
      Fabricate(:mention, account: account, status: status)
      Fabricate(:status, account: account,  id: 10)
      Fabricate(:status, account: other,    id: 11)
      Fabricate(:status, account: followed, id: 12, visibility: :private)
      Fabricate(:status, account: followed, id: 13, visibility: :direct)
      Fabricate(:status, account: account,  id: 14, visibility: :direct)
      mention = Fabricate(:status, account: followed, id: 15, visibility: :private)
      Fabricate(:mention, account: account, status: mention)
    end

    context 'when feed is generated' do
      before do
        stub_const 'FeedManager::MAX_ITEMS', 7
        FeedManager.instance.populate_home(account)
      end

      it 'gets statuses with ids in the range from redis with database' do
        results = subject.get(5)

        expect(results.map(&:id)).to eq [15, 14, 12, 10, 3]
      end

      it 'with since_id present' do
        results = subject.get(5, nil, 3, nil)
        expect(results.map(&:id)).to eq [15, 14, 12, 10]
      end

      it 'with min_id present' do
        results = subject.get(3, nil, nil, 0)
        expect(results.map(&:id)).to eq [3, 2, 1]
      end
    end

    context 'when feed is only partial' do
      before do
        stub_const 'FeedManager::MAX_ITEMS', 5
        FeedManager.instance.populate_home(account)
      end

      it 'gets statuses with ids in the range from redis with database' do
        results = subject.get(5)

        expect(results.map(&:id)).to eq [15, 14, 12, 10, 3]
      end

      it 'with since_id present' do
        results = subject.get(5, nil, 3, nil)
        expect(results.map(&:id)).to eq [15, 14, 12, 10]
      end

      it 'with min_id present' do
        results = subject.get(3, nil, nil, 0)
        expect(results.map(&:id)).to eq [3, 2, 1]
      end
    end

    context 'when feed is being generated' do
      before do
        stub_const 'FeedManager::MAX_ITEMS', 0
        redis.hset("account:#{account.id}:regeneration", { 'status' => 'running' })
      end

      it 'returns from database' do
        results = subject.get(5)

        expect(results.map(&:id)).to eq [15, 14, 12, 10, 3]
      end

      it 'builds filtering relationships once for the candidate collection' do
        allow(FeedManager.instance).to receive(:build_crutches).and_call_original

        subject.get(5)

        expect(FeedManager.instance).to have_received(:build_crutches).once
      end

      it 'with since_id present' do
        results = subject.get(5, nil, 3, nil)
        expect(results.map(&:id)).to eq [15, 14, 12, 10]
      end

      it 'with min_id present' do
        results = subject.get(3, nil, nil, 0)
        expect(results.map(&:id)).to eq [3, 2, 1]
      end

      it 'groups repeated boosts loaded from the database' do
        other_followed = Fabricate(:account)
        account.follow!(other_followed)
        original = Fabricate(:status, account: other, id: 20)
        Fabricate(:status, account: followed, id: 21, reblog: original)
        Fabricate(:status, account: other_followed, id: 22, reblog: original)

        results = subject.get(10)

        expect(results.map(&:id)).to include(22)
        expect(results.map(&:id)).to_not include(21)
      end

      it 'groups repeated boosts across database pagination requests' do
        other_followed = Fabricate(:account)
        account.follow!(other_followed)
        original = Fabricate(:status, account: other, id: 20)
        Fabricate(:status, account: followed, id: 21, reblog: original)
        Fabricate(:status, account: other_followed, id: 22, reblog: original)

        results = subject.get(10, 22)

        expect(results.map(&:id)).to_not include(21)
      end

      it 'keeps repeated boosts when boost grouping is disabled' do
        account.user.settings['aggregate_reblogs'] = false
        account.user.save!
        other_followed = Fabricate(:account)
        account.follow!(other_followed)
        original = Fabricate(:status, account: other, id: 20)
        Fabricate(:status, account: followed, id: 21, reblog: original)
        Fabricate(:status, account: other_followed, id: 22, reblog: original)

        results = subject.get(10)

        expect(results.map(&:id)).to include(21, 22)
      end
    end
  end
end
