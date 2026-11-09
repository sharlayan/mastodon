# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::AccountExtensions do
  describe 'MFM detection' do
    let(:account) { Fabricate(:account) }

    it 'recomputes the flag when profile text changes' do
      account.update!(note: '$[tada hello]')
      expect(account).to be_mfm

      account.update!(note: 'hello')
      expect(account).to_not be_mfm
    end
  end

  describe 'instance metadata refresh' do
    before do
      allow(InstanceMetadataUpdateWorker).to receive(:perform_async)
    end

    it 'schedules collection for new domains or stale metadata, but not for fresh colors or recent attempts' do
      Fabricate(:instance_metadata, domain: 'fresh.example', theme_color_updated_at: Time.current)
      Fabricate(:instance_metadata, domain: 'colorless.example', theme_color_updated_at: 30.days.ago, metadata_updated_at: 1.hour.ago)
      Fabricate(:instance_metadata, domain: 'old.example', theme_color_updated_at: 30.days.ago, metadata_updated_at: 2.days.ago)

      %w(new.example fresh.example colorless.example old.example).each { |domain| Fabricate(:account, domain: domain) }

      expect(InstanceMetadataUpdateWorker).to have_received(:perform_async).with('new.example')
      expect(InstanceMetadataUpdateWorker).to_not have_received(:perform_async).with('fresh.example')
      expect(InstanceMetadataUpdateWorker).to_not have_received(:perform_async).with('colorless.example')
      expect(InstanceMetadataUpdateWorker).to have_received(:perform_async).with('old.example')
    end
  end
end
