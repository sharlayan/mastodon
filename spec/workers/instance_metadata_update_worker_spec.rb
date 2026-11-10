# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InstanceMetadataUpdateWorker do
  let(:worker) { described_class.new }

  describe 'job uniqueness' do
    it 'keeps a single pending refresh per domain until it runs' do
      expect(described_class.get_sidekiq_options).to include('lock' => :until_executed, 'lock_ttl' => 1.hour.to_i)
    end
  end

  describe '#perform' do
    it 'calls FetchInstanceThemeColorService with the domain, with or without the manual refresh marker' do
      service = instance_double(FetchInstanceThemeColorService, call: nil)
      allow(FetchInstanceThemeColorService).to receive(:new).and_return(service)

      worker.perform('example.com')
      worker.perform('example.com', 'manual')

      expect(service).to have_received(:call).with('example.com').twice
    end

    it 'returns early for a blank or nil domain' do
      allow(FetchInstanceThemeColorService).to receive(:new)

      worker.perform('')
      worker.perform(nil)

      expect(FetchInstanceThemeColorService).to_not have_received(:new)
    end

    it 'logs errors without raising by default and re-raises them when priority is true' do
      service = instance_double(FetchInstanceThemeColorService)
      allow(FetchInstanceThemeColorService).to receive(:new).and_return(service)
      allow(service).to receive(:call).and_raise(StandardError.new('test error'))
      allow(Rails.logger).to receive(:error)

      expect { worker.perform('example.com') }.to_not raise_error
      expect(Rails.logger).to have_received(:error).with(/Failed to update instance metadata/)
      expect { worker.perform('example.com', priority: true) }.to raise_error(StandardError, 'test error')
    end
  end
end
