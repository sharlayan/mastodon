# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Scheduler::FederationRequestStatisticsCleanupScheduler do
  subject { described_class.new }

  describe '#perform' do
    it 'removes expired flush batch claims and request statistics and keeps recent ones' do
      FederationRequestFlushBatch.create!(batch_key: 'old', created_at: (FederationRequestFlushBatch::RETENTION_PERIOD + 1.day).ago)
      FederationRequestFlushBatch.create!(batch_key: 'recent', created_at: 1.day.ago)
      Fabricate(:federation_request_statistic, domain: 'old.example', bucket_at: (FederationRequestStatistic::RETENTION_PERIOD + 1.day).ago)
      Fabricate(:federation_request_statistic, domain: 'recent.example', bucket_at: 1.day.ago)

      subject.perform

      expect(FederationRequestFlushBatch.pluck(:batch_key)).to eq(['recent'])
      expect(FederationRequestStatistic.pluck(:domain)).to eq(['recent.example'])
    end
  end
end
