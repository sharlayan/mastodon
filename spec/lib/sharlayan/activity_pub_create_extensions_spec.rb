# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::ActivityPubCreateExtensions do
  subject(:activity) { ActivityPub::Activity::Create.allocate }

  describe '#sharlayan_status_params' do
    it 'maps MFM source and limited scope from the parser without retaining source text for non-MFM statuses' do
      mfm_parser = instance_double(
        ActivityPub::Parser::StatusParser,
        mfm?: true,
        mfm_source_text: '$[tada hello]',
        limited_scope: 'circle'
      )
      plain_parser = instance_double(ActivityPub::Parser::StatusParser, mfm?: false, limited_scope: nil)

      expect(activity.send(:sharlayan_status_params, mfm_parser)).to eq(
        mfm: true,
        mfm_text: '$[tada hello]',
        limited_scope: 'circle'
      )
      expect(activity.send(:sharlayan_status_params, plain_parser)).to eq(
        mfm: false,
        mfm_text: nil,
        limited_scope: nil
      )
    end

    it 'suppresses the public timeline stream only for a relay configured to do so' do
      suppressing = Fabricate(:account, domain: 'relay.example', inbox_url: 'https://relay.example/inbox')
      streaming = Fabricate(:account, domain: 'other-relay.example', inbox_url: 'https://other-relay.example/inbox')
      Fabricate(:relay, inbox_url: suppressing.inbox_url, state: :accepted, suppress_public_timeline_stream: true)
      Fabricate(:relay, inbox_url: streaming.inbox_url, state: :accepted)

      activity.instance_variable_set(:@options, { relayed_through_actor: suppressing })
      expect(activity.send(:relay_public_timeline_stream_suppressed?)).to be(true)

      other_activity = ActivityPub::Activity::Create.allocate
      other_activity.instance_variable_set(:@options, { relayed_through_actor: streaming })
      expect(other_activity.send(:relay_public_timeline_stream_suppressed?)).to be(false)
    end
  end

  describe '#download_remote_media_with_budget!' do
    let(:budget) { RemoteMediaDownloadBudget.new(byte_limit: 200, time_limit: 60) }

    def media_double(file_size:, thumbnail_size: nil)
      instance_double(
        MediaAttachment,
        remote_url: 'https://remote.example/file.png',
        thumbnail_remote_url: 'https://remote.example/thumb.png',
        file_file_size: file_size,
        thumbnail_file_size: thumbnail_size
      ).tap do |media|
        allow(media).to receive(:download_file!)
        allow(media).to receive(:download_thumbnail!)
      end
    end

    it 'downloads the file and thumbnail within the shared budget' do
      media_attachment = media_double(file_size: 40, thumbnail_size: 10)

      activity.send(:download_remote_media_with_budget!, media_attachment, budget)

      expect(media_attachment).to have_received(:download_file!).with(size_limit: 200).ordered
      expect(media_attachment).to have_received(:download_thumbnail!).with(size_limit: 160).ordered
      expect(budget.size_limit(1_000)).to eq(150)
    end

    it 'stops before the thumbnail when the file exhausts the budget' do
      media_attachment = media_double(file_size: 200)

      activity.send(:download_remote_media_with_budget!, media_attachment, budget)

      expect(media_attachment).to have_received(:download_file!).with(size_limit: 200)
      expect(media_attachment).to_not have_received(:download_thumbnail!)
    end

    it 'charges the full allowance when a download is discarded' do
      media_attachment = media_double(file_size: nil)

      activity.send(:download_remote_media_with_budget!, media_attachment, budget)

      expect(budget).to_not be_available
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

    it 'rejects relay delivery from a domain configured to reject relays and keeps it for an unrestricted domain' do
      allow(DomainBlock).to receive(:reject_relay?).with('remote.example').and_return(true)
      expect(activity.send(:accepted_through_relay?)).to be false

      allow(DomainBlock).to receive(:reject_relay?).with('remote.example').and_return(false)
      expect(relay_activity_class.new(instance_double(Account, domain: 'remote.example')).send(:accepted_through_relay?)).to be true
    end
  end
end
