# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PostStatusService do
  subject(:service) { described_class.new }

  let(:author) { Fabricate(:account) }
  let(:account) { Fabricate(:account) }
  let(:recipient) { Fabricate(:account) }
  let(:remote) { Fabricate(:account, domain: 'remote.example', protocol: :activitypub) }
  let(:outsider) { Fabricate(:account) }
  let(:parent) { Fabricate(:status, account: author, visibility: :limited, limited_scope: :circle) }
  let(:options) { { text: 'A reply', visibility: 'private', limited_scope: 'reply', thread: parent } }

  before do
    parent.mentions.create!(account: account, silent: true)
    parent.mentions.create!(account: recipient, silent: true)
    parent.mentions.create!(account: remote, silent: true)
  end

  it 'inherits hidden recipients and the parent author without opening access to other followers' do
    outsider.follow!(account)
    status = service.call(account, **options.merge(text: "@#{author.acct} A reply", allowed_mentions: [author.id]))

    expect(status).to have_attributes(visibility: 'limited', limited_scope: 'reply')
    expect(status.mentions.map(&:account_id)).to contain_exactly(author.id, recipient.id, remote.id)
    expect(status.mentions.find_by(account: author)).to_not be_silent
    expect(status.mentions.find_by(account: recipient)).to be_silent
    expect(status.mentions.find_by(account: remote)).to be_silent
    expect([account, recipient, outsider, nil].map { |viewer| StatusPolicy.new(viewer, status).show? }).to eq([true, true, false, false])
    remote.update!(shared_inbox_url: 'https://remote.example/inbox')
    expect(StatusReachFinder.new(status).inboxes).to contain_exactly(remote.inbox_url)
    expect(ActivityPub::TagManager.instance.to(status)).to contain_exactly(ActivityPub::TagManager.instance.uri_for(author))
    expect(ActivityPub::TagManager.instance.cc(status)).to be_empty
    author.update!(suspended_at: Time.now.utc)
    expect(ActivityPub::TagManager.instance.to(status)).to be_empty
  end

  it 'rejects an outside mention and a quote before persisting or distributing a reply' do
    quoted = Fabricate(:status)

    expect { service.call(account, **options.merge(text: "@#{outsider.acct} outside", allowed_mentions: [outsider.id])) }
      .to raise_error(Mastodon::ValidationError)
    expect { service.call(account, **options.merge(quoted_status: quoted)) }
      .to raise_error(Mastodon::ValidationError)
    expect(account.statuses.reload).to be_empty
  end

  it 'requires an accessible limited parent and rejects incompatible scope options' do
    public_parent = Fabricate(:status)
    direct_parent = Fabricate(:status, visibility: :direct)
    direct_parent.mentions.create!(account: account)
    other_parent = Fabricate(:status, visibility: :limited)

    [options.except(:thread), options.merge(thread: public_parent), options.merge(thread: direct_parent), options.merge(visibility: 'public'), options.merge(visibility: 'direct'), options.merge(limited_scope: 'mutual'), options.merge(circle_id: '1')].each do |params|
      expect { service.call(account, **params) }.to raise_error(Mastodon::ValidationError)
    end
    expect { service.call(account, **options.merge(thread: other_parent)) }.to raise_error(Mastodon::NotPermittedError)
    expect(account.statuses.reload).to be_empty
  end

  it 'preserves the audience during edits and atomically rejects a new recipient' do
    status = service.call(account, **options)
    recipient_ids = status.mentions.pluck(:account_id)
    PreviewCardsStatus.create!(status: status, preview_card: Fabricate(:preview_card))
    stub_request(:get, 'https://example.com/new').to_return(status: 404)
    allow(LinkCrawlWorker).to receive(:perform_async)
    UpdateStatusService.new.call(status, account.id, text: "@#{recipient.acct} edited https://example.com/new")
    expect(status.reload.preview_card).to be_nil
    expect(LinkCrawlWorker).to have_received(:perform_async).with(status.id)
    expect(status.edits.last.text).to include('https://example.com/new')
    previous_text = status.reload.text
    previous_edits = status.edits.count
    parent.mentions.create!(account: outsider, silent: true)

    expect { UpdateStatusService.new.call(status, account.id, text: "@#{outsider.acct} outside") }.to raise_error(Mastodon::ValidationError)
    expect(status.reload.text).to eq(previous_text)
    expect(status.edits.count).to eq(previous_edits)
    expect(status.mentions.pluck(:account_id)).to match_array(recipient_ids)
    expect(status.mentions.find_by(account: recipient)).to_not be_silent
    expect(status.mentions.find_by(account: author)).to be_silent
  end

  it 'freezes scheduled recipients and inherits local-only through publication' do
    parent.update!(local_only: true)
    scheduled = service.call(account, **options.merge(local_only: false, scheduled_at: 2.hours.from_now))
    initial_audience = scheduled.params.fetch('limited_reply_account_ids')
    parent.mentions.create!(account: outsider, silent: true)

    expect(scheduled.params).to include('limited_scope' => 'reply', 'local_only' => true)
    expect(initial_audience).to match_array([author, account, recipient, remote].map { |target| target.id.to_s })
    expect { PublishScheduledStatusWorker.new.perform(scheduled.id) }.to_not enqueue_sidekiq_job(ActivityPub::DistributionWorker)

    status = account.statuses.reload.last
    expect(status).to have_attributes(visibility: 'limited', limited_scope: 'reply', local_only: true)
    expect(status.mentions.pluck(:account_id)).to contain_exactly(author.id, recipient.id, remote.id)
    expect(StatusPolicy.new(remote, status).show?).to be false
  end

  it 'supports self replies and remote parents without resolving a Group conversation' do
    own_parent = Fabricate(:status, account: account, visibility: :limited, limited_scope: :personal)
    own_reply = service.call(account, **options.merge(thread: own_parent))
    remote_parent = Fabricate(:status, account: remote, visibility: :limited, limited_scope: :reply, uri: 'https://remote.example/statuses/parent')
    remote_parent.mentions.create!(account: account, silent: true)
    remote_parent.mentions.create!(account: recipient, silent: true)
    remote_reply = service.call(account, **options.merge(thread: remote_parent))

    expect(own_reply).to have_attributes(visibility: 'limited', limited_scope: 'reply')
    expect(own_reply.mentions).to be_empty
    expect(remote_reply.mentions.pluck(:account_id)).to contain_exactly(remote.id, recipient.id)
    expect(ActivityPub::TagManager.instance.to(remote_reply)).to contain_exactly(ActivityPub::TagManager.instance.uri_for(remote))
  end

  it 'does not expand a group recipient to its followers collection or add interaction inboxes' do
    remote.update!(actor_type: 'Group')
    outsider_remote = Fabricate(:account, domain: 'outside.example', protocol: :activitypub)
    status = service.call(account, **options)
    Fabricate(:favourite, account: outsider_remote, status: status)

    expect(ActivityPub::TagManager.instance.to(status)).to_not include(ActivityPub::TagManager.instance.followers_uri_for(remote))
    expect(StatusReachFinder.new(status, unsafe: true).inboxes).to contain_exactly(remote.inbox_url)
  end

  it 'retains only unblocked inherited recipients' do
    account.block!(recipient)
    status = service.call(account, **options)

    expect(status.mentions.pluck(:account_id)).to contain_exactly(author.id, remote.id)
    expect(StatusPolicy.new(recipient, status).show?).to be false
  end

  it 'fans out only to mentioned followers and never to public streams', :inline_jobs do
    recipient.follow!(account)
    recipient.follow!(author)
    outsider.follow!(account)
    allow(ActivityPub::DistributionWorker).to receive(:perform_async)
    allow(redis).to receive(:publish)
    status = service.call(account, **options)

    expect(HomeFeed.new(recipient).get(10).map(&:id)).to include(status.id)
    expect(HomeFeed.new(outsider).get(10).map(&:id)).to_not include(status.id)
    expect(redis).to_not have_received(:publish).with('timeline:public', anything)
    expect(redis).to_not have_received(:publish).with('timeline:public:local', anything)
  end
end
