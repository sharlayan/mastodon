# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::FanOutOnWriteServiceExtensions do
  let(:last_active_at) { Time.now.utc }
  let!(:author)   { Fabricate(:user, current_sign_in_at: last_active_at).account }
  let!(:fan)      { Fabricate(:user, current_sign_in_at: last_active_at).account }
  let!(:follower) { Fabricate(:user, current_sign_in_at: last_active_at).account }
  let(:channel)   { MisskeyChannel.create!(account: author, name: 'Lobby') }

  before do
    follower.follow!(author)
    MisskeyChannelFollowing.create!(account: fan, misskey_channel: channel)
    allow(redis).to receive(:publish)
  end

  def post_in_channel(text = 'in channel')
    PostStatusService.new.call(author, text: text, visibility: 'public', local_only: true, misskey_channel_id: channel.id)
  end

  def home_feed_of(account)
    HomeFeed.new(account).get(10).map(&:id)
  end

  it 'links the note in the post transaction, keeps it local and counts channel activity' do
    status = nil

    expect { status = post_in_channel }.to_not enqueue_sidekiq_job(ActivityPub::DistributionWorker)
    post_in_channel('again')

    expect(status.reload).to have_attributes(local_only: true, visibility: 'public')
    expect(MisskeyChannelNote.find_by(status: status)).to have_attributes(misskey_channel_id: channel.id, account_id: author.id)
    expect(channel.reload).to have_attributes(notes_count: 2, users_count: 1)
    expect(channel.last_noted_at).to be_present
  end

  it 'delivers only to channel followers and stays out of public timelines', :inline_jobs do
    plain = PostStatusService.new.call(author, text: 'plain', visibility: 'public')
    status = post_in_channel

    expect(status.id).to be_in(home_feed_of(fan))
    expect(status.id).to_not be_in(home_feed_of(follower))
    expect(status.id).to_not be_in(home_feed_of(author))
    expect(plain.id).to be_in(home_feed_of(follower))

    expect(PublicFeed.new(follower, local: true).get(10).map(&:id)).to eq([plain.id])
    expect(redis).to have_received(:publish).with('timeline:public:local', anything).once
  end

  it 'filters muted channels and renotes of their notes from home and public feeds' do
    status = post_in_channel
    renote = ReblogService.new.call(follower, status)
    MisskeyChannelMuting.create!(account: fan, misskey_channel: channel)
    fan.follow!(follower)

    expect(FeedManager.instance.filter?(:home, status, fan)).to be(true)
    expect(FeedManager.instance.filter?(:home, renote, fan)).to be(true)
    expect(FeedManager.instance.filter?(:home, renote, author)).to be(false)
    expect(PublicFeed.new(fan, local: true, with_reblogs: true).get(10)).to be_empty
    expect(PublicFeed.new(author, local: true, with_reblogs: true).get(10).map(&:id)).to eq([renote.id])
  end
end
