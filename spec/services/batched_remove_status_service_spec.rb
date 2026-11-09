# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BatchedRemoveStatusService, :inline_jobs do
  subject { described_class.new }

  let!(:alice)  { Fabricate(:account) }
  let!(:bob)    { Fabricate(:account, username: 'bob', domain: 'example.com') }
  let!(:jeff)   { Fabricate(:account) }
  let!(:hank)   { Fabricate(:account, username: 'hank', protocol: :activitypub, domain: 'example.com', inbox_url: 'http://example.com/inbox') }

  let(:status_alice_hello) { PostStatusService.new.call(alice, text: "Hello @#{bob.pretty_acct}") }
  let(:status_alice_other) { PostStatusService.new.call(alice, text: 'Another status') }

  before do
    allow(redis).to receive_messages(publish: nil)

    stub_request(:post, 'http://example.com/inbox').to_return(status: 200)

    jeff.user.update(current_sign_in_at: Time.zone.now)
    jeff.follow!(alice)
    hank.follow!(alice)

    status_alice_hello
    status_alice_other
  end

  it 'removes status records, removes from author and local follower feeds, notifies stream, sends delete' do
    subject.call([status_alice_hello, status_alice_other])

    expect { Status.find(status_alice_hello.id) }
      .to raise_error ActiveRecord::RecordNotFound
    expect { Status.find(status_alice_other.id) }
      .to raise_error ActiveRecord::RecordNotFound

    expect(feed_ids_for(alice))
      .to_not include(status_alice_hello.id, status_alice_other.id)

    expect(feed_ids_for(jeff))
      .to_not include(status_alice_hello.id, status_alice_other.id)

    expect(redis)
      .to have_received(:publish)
      .with("timeline:#{jeff.id}", any_args).at_least(:once)

    expect(redis)
      .to have_received(:publish)
      .with('timeline:public', any_args).at_least(:once)

    expect(a_request(:post, 'http://example.com/inbox'))
      .to have_been_made.at_least_once
  end

  it 'removes statuses from matching antenna feeds without querying antennas for each status' do
    antenna = Fabricate(:antenna, account: jeff, any_keywords: false, keywords: %w(Another))
    other_antenna = Fabricate(:antenna, account: jeff, any_keywords: false, keywords: %w(unrelated))
    statuses = Array.new(5) { PostStatusService.new.call(alice, text: 'Another antenna status') }
    feed_key = FeedManager.instance.key(:antenna, antenna.id)
    other_feed_key = FeedManager.instance.key(:antenna, other_antenna.id)
    statuses.each do |status|
      redis.zadd(feed_key, status.id, status.id)
      redis.zadd(other_feed_key, status.id, status.id)
    end
    antenna_queries = []
    callback = ->(*, payload) { antenna_queries << payload[:sql] if payload[:sql].match?(/antenna|media_attachments|polls/) && !payload[:cached] }

    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { subject.call(statuses) }

    expect(redis.zrange(feed_key, 0, -1)).to be_empty
    expect(redis.zrange(other_feed_key, 0, -1)).to match_array(statuses.map { |status| status.id.to_s })
    expect(antenna_queries.size).to be <= 8
  end

  def feed_ids_for(account)
    HomeFeed
      .new(account)
      .get(10)
      .pluck(:id)
  end
end
