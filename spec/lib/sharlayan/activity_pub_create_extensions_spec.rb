# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::ActivityPubCreateExtensions do
  subject(:activity) { ActivityPub::Activity::Create.allocate }

  describe '#sharlayan_status_params' do
    it 'maps MFM source and limited scope from the parser' do
      parser = instance_double(
        ActivityPub::Parser::StatusParser,
        mfm?: true,
        mfm_source_text: '$[tada hello]',
        limited_scope: 'circle'
      )

      expect(activity.send(:sharlayan_status_params, parser)).to eq(
        mfm: true,
        mfm_text: '$[tada hello]',
        limited_scope: 'circle'
      )
    end

    it 'does not retain source text for a non-MFM status' do
      parser = instance_double(ActivityPub::Parser::StatusParser, mfm?: false, limited_scope: nil)

      expect(activity.send(:sharlayan_status_params, parser)).to eq(
        mfm: false,
        mfm_text: nil,
        limited_scope: nil
      )
    end

    it 'suppresses the public timeline stream for a relay configured to do so' do
      relay_account = Fabricate(:account, domain: 'relay.example', inbox_url: 'https://relay.example/inbox')
      Fabricate(:relay, inbox_url: relay_account.inbox_url, state: :accepted, suppress_public_timeline_stream: true)

      activity.instance_variable_set(:@options, { relayed_through_actor: relay_account })

      expect(activity.send(:relay_public_timeline_stream_suppressed?)).to be(true)
    end

    it 'does not suppress the public timeline stream for a relay with it enabled' do
      relay_account = Fabricate(:account, domain: 'relay.example', inbox_url: 'https://relay.example/inbox')
      Fabricate(:relay, inbox_url: relay_account.inbox_url, state: :accepted)

      activity.instance_variable_set(:@options, { relayed_through_actor: relay_account })

      expect(activity.send(:relay_public_timeline_stream_suppressed?)).to be(false)
    end
  end

  describe '#download_remote_media_with_budget!' do
    it 'downloads the file and thumbnail within the shared budget' do
      media_attachment = instance_double(
        MediaAttachment,
        file_file_size: 40,
        thumbnail_file_size: 10
      )
      budget = instance_double(RemoteMediaDownloadBudget)

      allow(budget).to receive(:size_limit).with(MediaAttachment::VIDEO_LIMIT).and_return(100)
      allow(budget).to receive(:size_limit).with(MediaAttachment::IMAGE_LIMIT).and_return(60)
      allow(budget).to receive(:available?).and_return(true)
      allow(budget).to receive(:consume)
      allow(media_attachment).to receive(:download_file!)
      allow(media_attachment).to receive(:download_thumbnail!)

      activity.send(:download_remote_media_with_budget!, media_attachment, budget)

      expect(media_attachment).to have_received(:download_file!).with(size_limit: 100).ordered
      expect(budget).to have_received(:consume).with(40).ordered
      expect(media_attachment).to have_received(:download_thumbnail!).with(size_limit: 60).ordered
      expect(budget).to have_received(:consume).with(10).ordered
    end

    it 'stops before the thumbnail when the file exhausts the budget' do
      media_attachment = instance_double(MediaAttachment, file_file_size: 100)
      budget = instance_double(RemoteMediaDownloadBudget)

      allow(budget).to receive(:size_limit).with(MediaAttachment::VIDEO_LIMIT).and_return(100)
      allow(budget).to receive(:available?).and_return(false)
      allow(budget).to receive(:consume)
      allow(media_attachment).to receive(:download_file!)
      allow(media_attachment).to receive(:download_thumbnail!)

      activity.send(:download_remote_media_with_budget!, media_attachment, budget)

      expect(media_attachment).to have_received(:download_file!).with(size_limit: 100)
      expect(media_attachment).to_not have_received(:download_thumbnail!)
    end
  end

  describe '#sharlayan_quote_attributes' do
    it 'marks quotes parsed from Misskey' do
      parser = instance_double(ActivityPub::Parser::StatusParser, from_misskey?: true)

      expect(activity.send(:sharlayan_quote_attributes, parser)).to eq(from_misskey: true)
    end
  end

  describe '#accepted_through_relay?' do
    subject(:activity) { relay_activity_class.new(instance_double(Account, domain: 'remote.example')) }

    let(:relay_activity_class) do
      Class.new do
        prepend Sharlayan::ActivityPubCreateExtensions

        def initialize(account)
          @account = account
        end

        private

        def requested_through_relay?
          true
        end
      end
    end

    it 'rejects relay delivery from a domain configured to reject relays' do
      allow(DomainBlock).to receive(:reject_relay?).with('remote.example').and_return(true)

      expect(activity.send(:accepted_through_relay?)).to be false
    end

    it 'keeps relay delivery enabled for an unrestricted domain' do
      allow(DomainBlock).to receive(:reject_relay?).with('remote.example').and_return(false)

      expect(activity.send(:accepted_through_relay?)).to be true
    end
  end
end
