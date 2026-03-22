# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InstanceMetadataUpdateWorker do
  let(:worker) { described_class.new }

  describe '#perform' do
    it 'calls FetchInstanceThemeColorService with the domain' do
      service = instance_double(FetchInstanceThemeColorService)
      allow(FetchInstanceThemeColorService).to receive(:new).and_return(service)
      allow(service).to receive(:call)

      worker.perform('example.com')

      expect(service).to have_received(:call).with('example.com')
    end

    it 'returns early for blank domain' do
      allow(FetchInstanceThemeColorService).to receive(:new)

      worker.perform('')

      expect(FetchInstanceThemeColorService).to_not have_received(:new)
    end

    it 'returns early for nil domain' do
      allow(FetchInstanceThemeColorService).to receive(:new)

      worker.perform(nil)

      expect(FetchInstanceThemeColorService).to_not have_received(:new)
    end

    it 'logs errors and does not raise by default' do
      service = instance_double(FetchInstanceThemeColorService)
      allow(FetchInstanceThemeColorService).to receive(:new).and_return(service)
      allow(service).to receive(:call).and_raise(StandardError.new('test error'))
      allow(Rails.logger).to receive(:error)

      expect { worker.perform('example.com') }.to_not raise_error

      expect(Rails.logger).to have_received(:error).with(/Failed to update instance metadata/)
    end

    it 're-raises errors when priority is true' do
      service = instance_double(FetchInstanceThemeColorService)
      allow(FetchInstanceThemeColorService).to receive(:new).and_return(service)
      allow(service).to receive(:call).and_raise(StandardError.new('test error'))

      allow(Rails.logger).to receive(:error)

      expect { worker.perform('example.com', priority: true) }.to raise_error(StandardError, 'test error')
    end
  end
end
