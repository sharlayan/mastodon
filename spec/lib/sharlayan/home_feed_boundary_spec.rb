# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::HomeFeedBoundary do
  subject { described_class.resolve(account, status_id) }

  let(:account)   { Fabricate(:account) }
  let(:bob)       { Fabricate(:account) }
  let(:stranger)  { Fabricate(:account) }
  let(:original)  { Fabricate(:status, account: bob) }
  let(:status_id) { original.id }

  before { account.follow!(bob) }

  context 'when the status has no reblog in the feed' do
    it { is_expected.to be_nil }
  end

  context 'when a followed account reblogged the status' do
    let!(:reblog) { Fabricate(:status, account: bob, reblog: original) }

    it 'returns the id of the reblog' do
      expect(subject).to eq reblog.id
    end
  end

  context 'when the account itself reblogged the status' do
    let!(:reblog) { Fabricate(:status, account: account, reblog: original) }

    before do
      account.user.settings['display_own_boosts'] = true
      account.user.save!
    end

    it 'returns the id of the reblog' do
      expect(subject).to eq reblog.id
    end
  end

  context 'when an older own reblog is hidden by the user preference' do
    let!(:hidden) { Fabricate(:status, account: account, reblog: original) }
    let!(:shown) { Fabricate(:status, account: bob, reblog: original) }

    before do
      account.user.settings['display_own_boosts'] = false
      account.user.save!
    end

    it 'uses the visible followed reblog as the pagination boundary' do
      expect(subject).to eq shown.id
    end

    context 'when the own reblog is still present in the cached feed' do
      before { redis.zadd(FeedManager.instance.key(:home, account.id), hidden.id, hidden.id) }

      it 'preserves the cached own reblog boundary using its exact member id' do
        expect(subject).to eq hidden.id
      end
    end
  end

  context 'when only an unfollowed account reblogged the status' do
    before { Fabricate(:status, account: stranger, reblog: original) }

    it { is_expected.to be_nil }
  end

  context 'when the only reblog is hidden from the home feed' do
    before do
      account.mute!(bob, notifications: false)
      Fabricate(:status, account: bob, reblog: original)
    end

    it { is_expected.to be_nil }
  end

  context 'when an older reblog is hidden from the home feed' do
    let(:muted)   { Fabricate(:account) }
    let!(:hidden) { Fabricate(:status, account: muted, reblog: original) }
    let!(:shown)  { Fabricate(:status, account: bob, reblog: original) }

    before do
      account.follow!(muted)
      account.mute!(muted, notifications: false)
    end

    it 'skips the hidden reblog and returns the visible one' do
      expect(subject).to eq shown.id
      expect(subject).to_not eq hidden.id
    end
  end

  context 'when several followed accounts reblogged the status' do
    let!(:first)  { Fabricate(:status, account: bob, reblog: original) }
    let!(:second) { Fabricate(:status, account: account, reblog: original) }

    it 'returns the oldest reblog so no entry is skipped' do
      expect([first.id, second.id].min).to eq subject
    end
  end

  context 'when the status id is blank' do
    let(:status_id) { nil }

    it { is_expected.to be_nil }
  end
end
