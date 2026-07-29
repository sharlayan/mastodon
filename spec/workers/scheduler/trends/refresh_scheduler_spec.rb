# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Scheduler::Trends::RefreshScheduler do
  let(:worker) { described_class.new }

  describe 'perform' do
    it 'refreshes trends when processing is enabled' do
      allow(Trends).to receive(:refresh!)

      worker.perform

      expect(Trends).to have_received(:refresh!)
    end

    it 'does not refresh trends when processing is disabled' do
      allow(LowResourceFeatures).to receive(:trends_processing_enabled?).and_return(false)
      allow(Trends).to receive(:refresh!)

      worker.perform

      expect(Trends).to_not have_received(:refresh!)
    end
  end
end
