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

  it 'skips blocked authors via FeedManager filtering' do
    owner.block!(author)
    antenna = Fabricate(:antenna, account: owner)
    status = Fabricate(:status, account: author, text: 'hello', visibility: :public)

    subject.call(status, false, mode: :home)

    expect(antenna_feed_of(antenna)).to_not include(status.id)
  end
end
