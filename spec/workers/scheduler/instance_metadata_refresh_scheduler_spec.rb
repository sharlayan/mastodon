# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Scheduler::InstanceMetadataRefreshScheduler do
  let(:scheduler) { described_class.new }

  describe '#perform' do
    before do
      allow(InstanceMetadataUpdateWorker).to receive(:perform_async)
    end

    context 'with missing info domains' do
      it 'enqueues workers for domains with missing software' do
        Fabricate(:instance_metadata, domain: 'missing-software.example.com', software: nil, instance_name: 'Test')
        scheduler.perform
        expect(InstanceMetadataUpdateWorker).to have_received(:perform_async).with('missing-software.example.com')
      end

      it 'rotates through incomplete domains by least recent attempt' do
        50.times { |i| Fabricate(:instance_metadata, domain: "recent#{i}.example.com", software: nil, instance_name: 'Test', metadata_updated_at: 1.minute.ago) }
        stale = Fabricate(:instance_metadata, domain: 'stale.example.com', software: nil, instance_name: 'Test', metadata_updated_at: 2.days.ago)

        scheduler.perform

        expect(InstanceMetadataUpdateWorker).to have_received(:perform_async).with(stale.domain)
      end

      it 'enqueues workers for domains with missing instance_name' do
        Fabricate(:instance_metadata, domain: 'missing-name.example.com', software: 'mastodon', instance_name: nil)
        scheduler.perform
        expect(InstanceMetadataUpdateWorker).to have_received(:perform_async).with('missing-name.example.com')
      end

      it 'enqueues workers for domains with empty software string' do
        Fabricate(:instance_metadata, domain: 'empty-software.example.com', software: '', instance_name: 'Test')
        scheduler.perform
        expect(InstanceMetadataUpdateWorker).to have_received(:perform_async).with('empty-software.example.com')
      end

      it 'enqueues a fresh domain immediately when the public posts count is missing' do
        Fabricate(:instance_metadata, domain: 'missing-posts.example.com', software: 'mastodon', instance_name: 'Test', local_posts_count: nil, theme_color_updated_at: 1.hour.ago, metadata_updated_at: 1.hour.ago)

        scheduler.perform

        expect(InstanceMetadataUpdateWorker).to have_received(:perform_async).with('missing-posts.example.com').once
      end
    end

    context 'with outdated domains' do
      it 'enqueues workers for domains with outdated theme_color' do
        Fabricate(:instance_metadata, domain: 'outdated.example.com', software: 'mastodon', instance_name: 'Test', local_posts_count: 1, theme_color_updated_at: 8.days.ago)
        scheduler.perform
        expect(InstanceMetadataUpdateWorker).to have_received(:perform_async).with('outdated.example.com')
      end
    end

    context 'with active remote domains' do
      it 'enqueues workers for active remote domains without metadata' do
        account = Fabricate(:account, domain: 'active-remote.example.com')
        Fabricate(:account_stat, account: account, last_status_at: 5.days.ago)

        scheduler.perform
        expect(InstanceMetadataUpdateWorker).to have_received(:perform_async).with('active-remote.example.com').at_least(:once)
      end

      it 'skips active domains that already have metadata in the active domains phase' do
        Fabricate(:instance_metadata, domain: 'has-metadata.example.com', software: 'mastodon', instance_name: 'Test', local_posts_count: 1, theme_color_updated_at: 1.hour.ago, metadata_updated_at: 1.hour.ago)
        account = Fabricate(:account, domain: 'has-metadata.example.com')
        Fabricate(:account_stat, account: account, last_status_at: 5.days.ago)

        allow(InstanceMetadataUpdateWorker).to receive(:perform_async)

        scheduler.perform

        expect(InstanceMetadataUpdateWorker).to_not have_received(:perform_async).with('has-metadata.example.com')
      end
    end

    it 'enqueues active domains without metadata when many active domains already have metadata' do
      200.times do |i|
        domain = "known#{i}.example.com"
        Fabricate(:instance_metadata, domain: domain, software: 'mastodon', instance_name: 'Test', local_posts_count: 1, theme_color_updated_at: 1.hour.ago, metadata_updated_at: 1.hour.ago)
        Fabricate(:account_stat, account: Fabricate(:account, domain: domain), last_status_at: 1.day.ago)
      end
      Fabricate(:account_stat, account: Fabricate(:account).tap { |account| account.update_column(:domain, 'new-remote.example.com') }, last_status_at: 1.day.ago)

      scheduler.perform

      expect(InstanceMetadataUpdateWorker).to have_received(:perform_async).with('new-remote.example.com')
    end

    it 'runs without error when no records exist' do
      expect { scheduler.perform }.to_not raise_error
    end
  end
end
