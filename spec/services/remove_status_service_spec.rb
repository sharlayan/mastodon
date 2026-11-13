# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RemoveStatusService, :inline_jobs do
  subject { described_class.new }

  let!(:alice)  { Fabricate(:account) }
  let!(:bob)    { Fabricate(:account, username: 'bob', domain: 'example.com') }
  let!(:jeff)   { Fabricate(:account) }
  let!(:hank)   { Fabricate(:account, username: 'hank', protocol: :activitypub, domain: 'example.com', inbox_url: 'http://example.com/inbox') }
  let!(:bill)   { Fabricate(:account, username: 'bill', protocol: :activitypub, domain: 'example2.com', inbox_url: 'http://example2.com/inbox') }

  before do
    stub_request(:post, hank.inbox_url).to_return(status: 200)
    stub_request(:post, bill.inbox_url).to_return(status: 200)

    jeff.follow!(alice)
    hank.follow!(alice)
  end

  context 'when removed status is not a reblog' do
    let!(:media_attachment) { Fabricate(:media_attachment, account: alice) }
    let!(:status) { PostStatusService.new.call(alice, text: "Hello @#{bob.pretty_acct} ThisIsASecret", media_ids: [media_attachment.id]) }

    before do
      FavouriteService.new.call(jeff, status)
      Fabricate(:status, account: bill, reblog: status, uri: 'hoge')
    end

    it 'removes status from notifications and from author and local follower home feeds, publishes to media timeline, sends delete activities' do
      allow(redis).to receive(:publish).with(any_args)

      expect { subject.call(status) }
        .to remove_status_from_notifications

      expect(home_feed_ids(alice))
        .to_not include(status.id)
      expect(home_feed_ids(jeff))
        .to_not include(status.id)

      expect(redis)
        .to have_received(:publish).with('timeline:public:media', { event: :delete, payload: status.id.to_s }.to_json)

      expect(delete_delivery(hank, status))
        .to have_been_made.once

      expect(delete_delivery(bill, status))
        .to have_been_made.once
    end

    def home_feed_ids(personage)
      HomeFeed
        .new(personage)
        .get(10)
        .pluck(:id)
    end

    def remove_status_from_notifications
      change { Notification.where(activity_type: 'Favourite', from_account: jeff, account: alice).count }
        .from(1)
        .to(0)
    end

    def delete_delivery(target, status)
      a_request(:post, target.inbox_url)
        .with(body: delete_activity_for(status))
    end

    def delete_activity_for(status)
      hash_including(
        'type' => 'Delete',
        'object' => {
          'type' => 'Tombstone',
          'id' => ActivityPub::TagManager.instance.uri_for(status),
          'atomUri' => OStatus::TagManager.instance.uri_for(status),
        }
      )
    end
  end

  context 'when preserved media include shared Drive pointers', inline_jobs: false do
    it 'privatizes owned attachments while leaving the shared Drive file accessible' do
      drive_file = alice.drive_files.create!(file: attachment_fixture('attachment.jpg'))
      deleted_status = Fabricate(:status, account: alice)
      kept_status = Fabricate(:status, account: alice)
      deleted_pointer = drive_file.build_pointer(alice).tap { |pointer| pointer.update!(status: deleted_status) }
      kept_pointer = drive_file.build_pointer(alice).tap { |pointer| pointer.update!(status: kept_status) }
      attachment = Fabricate(:media_attachment, account: alice, status: deleted_status)
      page = Fabricate(:page, account: alice, content: [{ 'id' => 'image', 'type' => 'image', 'fileId' => kept_pointer.id.to_s }])
      changed_paths = []
      allow(FileUtils).to receive(:chmod) { |_mask, path| changed_paths << path }

      subject.call(deleted_status, preserve: true)

      expect(changed_paths).to include(attachment.file.path(:original))
      expect(changed_paths).to_not include(drive_file.file.path(:original), drive_file.file.path(:small))
      expect(deleted_pointer.reload.drive_file).to eq(drive_file)
      expect(kept_pointer.reload.status).to eq(kept_status)
      expect(page.reload.attached_media).to include(kept_pointer)
    end
  end

  context 'when removed status is a private self-reblog' do
    let!(:original_status) { Fabricate(:status, account: alice, text: 'Hello ThisIsASecret', visibility: :private) }
    let!(:status) { ReblogService.new.call(alice, original_status) }

    it 'sends Undo activity to followers' do
      subject.call(status)

      expect(undo_delivery(hank, original_status))
        .to have_been_made.once
    end
  end

  context 'when removed status is public self-reblog' do
    let!(:original_status) { Fabricate(:status, account: alice, text: 'Hello ThisIsASecret', visibility: :public) }
    let!(:status) { ReblogService.new.call(alice, original_status) }

    it 'sends Undo activity to followers' do
      subject.call(status)

      expect(undo_delivery(hank, original_status))
        .to have_been_made.once
    end
  end

  context 'when removed status is a reblog of a non-follower' do
    let!(:original_status) { Fabricate(:status, account: bill, text: 'Hello ThisIsASecret', visibility: :public) }
    let!(:status) { ReblogService.new.call(alice, original_status) }

    it 'sends Undo activity to followers' do
      subject.call(status)

      expect(undo_delivery(bill, original_status))
        .to have_been_made.once
    end
  end

  def undo_delivery(target, status)
    a_request(:post, target.inbox_url)
      .with(body: undo_activity_for(status))
  end

  def undo_activity_for(status)
    hash_including(
      'type' => 'Undo',
      'object' => hash_including(
        'type' => 'Announce',
        'object' => ActivityPub::TagManager.instance.uri_for(status)
      )
    )
  end

  context 'when removed status is a quote of a local user', inline_jobs: false do
    let(:original_status) { Fabricate(:status, account: alice) }
    let(:status) { Fabricate(:status, account: jeff) }

    before do
      bill.follow!(jeff)
      Fabricate(:quote, status: status, quoted_status: original_status, state: :accepted)
      original_status.discard
    end

    it 'sends deletion without crashing' do
      expect { subject.call(status.reload) }
        .to enqueue_sidekiq_job(ActivityPub::DeliveryWorker).with(/Delete/, jeff.id, bill.inbox_url)
    end
  end
end
