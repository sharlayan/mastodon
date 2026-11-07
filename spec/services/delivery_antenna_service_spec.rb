# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DeliveryAntennaService do
  subject { described_class.new }

  let(:last_active_at) { Time.now.utc }
  let!(:owner)  { Fabricate(:user, current_sign_in_at: last_active_at).account }
  let!(:author) { Fabricate(:user, current_sign_in_at: last_active_at, account_attributes: { username: 'author' }).account }

  def antenna_feed_of(antenna)
    AntennaFeed.new(antenna).get(10).map(&:id)
  end

  around do |example|
    Sidekiq::Testing.inline! { example.run }
  end

  it 'inserts a matching status into the antenna feed' do
    antenna = Fabricate(:antenna, account: owner, any_keywords: false, keywords: %w(commission))
    status = Fabricate(:status, account: author, text: 'open for commission', visibility: :public)

    subject.call(status, false, mode: :home)

    expect(antenna_feed_of(antenna)).to include(status.id)
  end

  it 'skips delivery when antennas are disabled' do
    Setting.antenna_enabled = false
    antenna = Fabricate(:antenna, account: owner, any_keywords: false, keywords: %w(commission))
    status = Fabricate(:status, account: author, text: 'open for commission', visibility: :public)

    subject.call(status, false, mode: :home)

    expect(antenna_feed_of(antenna)).to_not include(status.id)
  ensure
    Setting.antenna_enabled = true
  end

  it 'does not insert a non-matching status' do
    antenna = Fabricate(:antenna, account: owner, any_keywords: false, keywords: %w(commission))
    status = Fabricate(:status, account: author, text: 'just chatting', visibility: :public)

    subject.call(status, false, mode: :home)

    expect(antenna_feed_of(antenna)).to_not include(status.id)
  end

  it 'honours with_media_only' do
    antenna = Fabricate(:antenna, account: owner, with_media_only: true)
    status = Fabricate(:status, account: author, text: 'no media here', visibility: :public)

    subject.call(status, false, mode: :home)

    expect(antenna_feed_of(antenna)).to_not include(status.id)
  end

  context 'with a private status' do
    let!(:follower) { Fabricate(:user, current_sign_in_at: last_active_at).account }
    let!(:stranger) { Fabricate(:user, current_sign_in_at: last_active_at).account }
    let(:status) { Fabricate(:status, account: author, text: 'followers only', visibility: :private) }

    before do
      follower.follow!(author)
      Fabricate.times(2, :account).each { |account| account.follow!(author) }
    end

    it 'delivers only to antennas owned by followers' do
      follower_antenna = Fabricate(:antenna, account: follower, any_keywords: false, keywords: %w(followers))
      stranger_antenna = Fabricate(:antenna, account: stranger, any_keywords: false, keywords: %w(followers))

      subject.call(status, false, mode: :home)

      expect(antenna_feed_of(follower_antenna)).to include(status.id)
      expect(antenna_feed_of(stranger_antenna)).to_not include(status.id)
    end

    it 'looks up follows only for antenna owners' do
      Fabricate(:antenna, account: follower, any_keywords: false, keywords: %w(followers))
      Fabricate(:antenna, account: stranger, any_keywords: false, keywords: %w(followers))
      allow(Follow).to receive(:where).and_call_original

      subject.call(status, false, mode: :home)

      expect(Follow).to have_received(:where).with(target_account_id: author.id, account_id: contain_exactly(follower.id, stranger.id))
    end
  end

  it 'does not deliver a direct status to antennas' do
    antenna = Fabricate(:antenna, account: owner, any_keywords: false, keywords: %w(hello))
    status = Fabricate(:status, account: author, text: 'hello', visibility: :direct)

    subject.call(status, false, mode: :home)

    expect(antenna_feed_of(antenna)).to_not include(status.id)
  end

  it 'skips blocked authors via FeedManager filtering' do
    owner.block!(author)
    antenna = Fabricate(:antenna, account: owner)
    status = Fabricate(:status, account: author, text: 'hello', visibility: :public)

    subject.call(status, false, mode: :home)

    expect(antenna_feed_of(antenna)).to_not include(status.id)
  end

  it 'skips boosts of authors the owner blocks or mutes' do
    blocked = Fabricate(:account, username: 'blocked')
    muted = Fabricate(:account, username: 'muted')
    owner.block!(blocked)
    owner.mute!(muted)
    antenna = Fabricate(:antenna, account: owner, any_keywords: false, keywords: %w(hello))
    blocked_boost = Fabricate(:status, account: author, reblog: Fabricate(:status, account: blocked, text: 'hello', visibility: :public))
    muted_boost = Fabricate(:status, account: author, reblog: Fabricate(:status, account: muted, text: 'hello', visibility: :public))

    subject.call(blocked_boost, false, mode: :home)
    subject.call(muted_boost, false, mode: :home)

    expect(antenna_feed_of(antenna)).to_not include(blocked_boost.id, muted_boost.id)
  end

  it 'skips boosts of authors that block the owner' do
    blocker = Fabricate(:account, username: 'blocker')
    blocker.block!(owner)
    antenna = Fabricate(:antenna, account: owner, any_keywords: false, keywords: %w(hello))
    boost = Fabricate(:status, account: author, reblog: Fabricate(:status, account: blocker, text: 'hello', visibility: :public))

    subject.call(boost, false, mode: :home)

    expect(antenna_feed_of(antenna)).to_not include(boost.id)
  end

  context 'with a silenced author' do
    let!(:follower) { Fabricate(:user, current_sign_in_at: last_active_at).account }

    before do
      author.silence!
      follower.follow!(author)
    end

    it 'delivers only to antennas whose owners follow the author' do
      follower_antenna = Fabricate(:antenna, account: follower, any_keywords: false, keywords: %w(hello))
      stranger_antenna = Fabricate(:antenna, account: owner, any_keywords: false, keywords: %w(hello))
      status = Fabricate(:status, account: author, text: 'hello', visibility: :public)

      subject.call(status, false, mode: :home)

      expect(antenna_feed_of(follower_antenna)).to include(status.id)
      expect(antenna_feed_of(stranger_antenna)).to_not include(status.id)
    end

    it 'does not deliver boosts of the author to owners who do not follow them' do
      booster = Fabricate(:account, username: 'booster')
      antenna = Fabricate(:antenna, account: owner, any_keywords: false, keywords: %w(hello))
      boost = Fabricate(:status, account: booster, reblog: Fabricate(:status, account: author, text: 'hello', visibility: :public))

      subject.call(boost, false, mode: :home)

      expect(antenna_feed_of(antenna)).to_not include(boost.id)
    end
  end
end
