# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Status do
  let(:account) { Fabricate(:account) }
  let(:remote_account) { Fabricate(:account, domain: 'example.com', protocol: :activitypub, inbox_url: 'https://example.com/inbox') }

  before do
    Setting.force_local_only = true
    allow(ActivityPub::DistributionWorker).to receive(:perform_async)
  end

  after do
    Setting.force_local_only = false
  end

  it 'forces local_only when a client explicitly asks to federate' do
    status = PostStatusService.new.call(account, text: 'explicit federate', local_only: false)

    expect(status.local_only).to be true
    expect(ActivityPub::DistributionWorker).to_not have_received(:perform_async)
  end

  it 'forces local_only when a client does not support the param at all' do
    status = PostStatusService.new.call(account, text: 'no param')

    expect(status.local_only).to be true
    expect(ActivityPub::DistributionWorker).to_not have_received(:perform_async)
  end

  it 'forces local_only on a string "false" from a lenient client' do
    status = PostStatusService.new.call(account, text: 'string false', local_only: 'false')

    expect(status.local_only).to be true
  end

  it 'forces local_only on a reblog of a remote status' do
    remote_status = Fabricate(:status, account: remote_account, uri: 'https://example.com/statuses/1', local: false)
    reblog = ReblogService.new.call(account, remote_status)

    expect(reblog.local_only).to be true
  end

  it 'forces local_only on a scheduled post when it is published' do
    scheduled = PostStatusService.new.call(account, text: 'scheduled', local_only: false, scheduled_at: 10.minutes.from_now)
    expect(scheduled).to be_a(ScheduledStatus)
    expect(scheduled.params['local_only']).to be false

    PublishScheduledStatusWorker.new.perform(scheduled.id)

    expect(described_class.where(account: account).order(:id).last.local_only).to be true
  end

  it 'still leaves remote statuses alone' do
    remote_status = Fabricate(:status, account: remote_account, uri: 'https://example.com/statuses/2', local: false)

    expect(remote_status.local_only).to be_nil
  end

  it 'does not force anything when the setting is off' do
    Setting.force_local_only = false
    status = PostStatusService.new.call(account, text: 'federated', local_only: false)

    expect(status.local_only).to be false
  end
end
