# frozen_string_literal: true

require 'rails_helper'

RSpec.describe HideStatusService do
  subject { described_class.new }

  let!(:alice) { Fabricate(:account) }
  let!(:bob)   { Fabricate(:account) }

  around do |example|
    ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') { example.run }
  end

  before do
    Setting.soft_hide_deletion = true
    bob.follow!(alice)
  end

  after do
    Setting.soft_hide_deletion = false
  end

  context 'when soft-hide is unavailable' do
    let!(:status) { PostStatusService.new.call(alice, text: 'Hello world') }

    context 'when roleplay mode is disabled' do
      around do |example|
        ClimateControl.modify(OC_ROLEPLAY_OPTION: 'false') { example.run }
      end

      it 'rejects the operation without changing the status' do
        expect { subject.call(status) }.to raise_error(Mastodon::NotPermittedError)
        expect(RpHiddenStatus.exists?(status_id: status.id)).to be(false)
      end
    end

    context 'when the setting is disabled' do
      before do
        Setting.soft_hide_deletion = false
      end

      it 'rejects the operation without changing the status' do
        expect { subject.call(status) }.to raise_error(Mastodon::NotPermittedError)
        expect(RpHiddenStatus.exists?(status_id: status.id)).to be(false)
      end
    end
  end

  context 'with a simple local status' do
    let!(:status) { PostStatusService.new.call(alice, text: 'Hello world') }

    it 'hides the status from the default scope, preserving the row, recording who hid it and updating counts and feeds' do
      allow(FeedManager.instance).to receive(:unpush_from_home)

      expect { subject.call(status, hidden_by_account_id: bob.id) }
        .to change { alice.reload.statuses_count }.by(-1)

      expect(Status.find_by(id: status.id)).to be_nil
      expect(Status.with_rp_hidden.find_by(id: status.id)).to eq(status)
      expect(RpHiddenStatus.exists?(status_id: status.id)).to be(true)
      expect(status.reload.rp_hidden?).to be(true)
      expect(RpHiddenStatus.find_by(status_id: status.id).hidden_by_account_id).to eq(bob.id)
      expect(FeedManager.instance).to have_received(:unpush_from_home).with(bob, status)
    end

    it 'is idempotent without a duplicate hidden record and cleans interactions when retrying' do
      subject.call(status)
      favourite = Fabricate(:favourite, status: status, account: bob)
      Fabricate(:notification, type: :favourite, activity: favourite, account: alice, from_account: bob)

      expect { subject.call(status) }
        .to not_change { alice.reload.statuses_count }
        .and(not_change { RpHiddenStatus.where(status_id: status.id).count })

      expect(Favourite.where(status_id: status.id)).to be_empty
      expect(Notification.where(activity_type: 'Favourite', activity_id: favourite.id)).to be_empty
    end

    it 'removes favourites, reactions, bookmarks and clip entries with their cached counts' do
      favourite = Fabricate(:favourite, status: status, account: bob)
      reaction = Fabricate(:status_reaction, status: status, account: bob, name: '👍')
      favourite_notification = Fabricate(:notification, type: :favourite, activity: favourite, account: alice, from_account: bob)
      reaction_notification = Fabricate(:notification, type: :reaction, activity: reaction, account: alice, from_account: bob)
      bookmark = Fabricate(:bookmark, status: status, account: bob)
      clip_status = ClipStatus.create!(clip: Fabricate(:clip, account: bob), status: status)

      subject.call(status)

      expect(Favourite.where(status_id: status.id)).to be_empty
      expect(StatusReaction.where(status_id: status.id)).to be_empty
      expect(Notification.where(id: [favourite_notification.id, reaction_notification.id])).to be_empty
      expect(status.reload.favourites_count).to eq(0)
      expect(status.reactions_count).to eq(0)
      expect(Bookmark.exists?(bookmark.id)).to be(false)
      expect(ClipStatus.exists?(clip_status.id)).to be(false)
    end
  end

  context 'when the status is boosted' do
    let!(:status) { PostStatusService.new.call(alice, text: 'Hello world') }
    let!(:reblog) { ReblogService.new.call(bob, status) }

    it 'hides the boost as well' do
      notification = Fabricate(:notification, type: :reblog, activity: reblog, account: alice, from_account: bob)

      subject.call(status)

      expect(Status.with_rp_hidden.find_by(id: reblog.id)).to be_present
      expect(reblog.reload.rp_hidden?).to be(true)
      expect(Notification.exists?(notification.id)).to be(false)
      expect(status.reload.reblogs_count).to eq(0)
    end

    it 'finishes hiding boosts when retrying an already hidden original' do
      RpHiddenStatus.create!(status: status)

      subject.call(status)

      expect(reblog.reload.rp_hidden?).to be(true)
      expect(status.reload.reblogs_count).to eq(0)
    end
  end

  context 'when the status has media' do
    let!(:media)  { Fabricate(:media_attachment, account: alice) }
    let!(:status) { PostStatusService.new.call(alice, text: 'With media', media_ids: [media.id]) }

    it 'queues the media hide worker' do
      subject.call(status)

      expect(HideStatusMediaWorker).to have_enqueued_sidekiq_job(status.id)
    end
  end

  context 'with a direct message' do
    it 'removes the message from the participants conversations' do
      bob_account = Fabricate(:user, account: Fabricate(:account, username: 'dmrecipient')).account
      first = PostStatusService.new.call(alice, text: '@dmrecipient first', visibility: 'direct')
      second = PostStatusService.new.call(alice, text: '@dmrecipient second', visibility: 'direct', thread: first)
      [first, second].each { |status| AccountConversation.add_status(bob_account, status) }

      subject.call(second)

      conversation = AccountConversation.find_by!(account: bob_account)
      expect(conversation.status_ids).to eq [first.id]
      expect(conversation.last_status_id).to eq first.id
    end
  end

  context 'with a boost that is already being removed' do
    it 'does not hide it again or decrement its counters twice' do
      status = PostStatusService.new.call(alice, text: 'boosted')
      booster = Fabricate(:account)
      boost = ReblogService.new.call(booster, status)
      boost.discard

      expect { subject.call(status) }.to_not(change { booster.reload.statuses_count })
      expect(RpHiddenStatus.exists?(status_id: boost.id)).to be(false)
    end
  end
end
