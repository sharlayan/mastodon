# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::FeedManagerExtensions do
  let(:owner) { Fabricate(:user, current_sign_in_at: Time.now.utc).account }
  let(:author) { Fabricate(:account, username: 'author') }
  let(:antenna) { Fabricate(:antenna, account: owner) }

  def antenna_feed_ids
    AntennaFeed.new(antenna).get(20).map(&:id)
  end

  def push(status)
    FeedManager.instance.push_to_antenna(antenna, status)
  end

  around do |example|
    Sidekiq::Testing.inline! { example.run }
  end

  it 'removes statuses from and mentioning a blocked account' do
    own = Fabricate(:status, account: author)
    mentioning = Fabricate(:status, account: Fabricate(:account))
    Fabricate(:mention, status: mentioning, account: author)
    other = Fabricate(:status, account: Fabricate(:account))
    [own, mentioning, other].each { |status| push(status) }

    BlockService.new.call(owner, author)

    expect(antenna_feed_ids).to contain_exactly(other.id)
  end

  it 'removes statuses and boosts by an account that blocks the owner' do
    own = Fabricate(:status, account: author)
    boost = Fabricate(:status, account: Fabricate(:account), reblog: Fabricate(:status, account: author))
    other = Fabricate(:status, account: Fabricate(:account))
    [own, boost, other].each { |status| push(status) }

    BlockService.new.call(author, owner)

    expect(antenna_feed_ids).to contain_exactly(other.id)
  end

  it 'removes statuses from a muted account' do
    own = Fabricate(:status, account: author)
    other = Fabricate(:status, account: Fabricate(:account))
    [own, other].each { |status| push(status) }

    MuteService.new.call(owner, author)

    expect(antenna_feed_ids).to contain_exactly(other.id)
  end

  it 'removes only private statuses after the follow ends' do
    owner.follow!(author)
    private_status = Fabricate(:status, account: author, visibility: :private)
    public_status = Fabricate(:status, account: author, visibility: :public)
    [private_status, public_status].each { |status| push(status) }

    UnfollowService.new.call(owner, author)

    expect(antenna_feed_ids).to contain_exactly(public_status.id)
  end
end
