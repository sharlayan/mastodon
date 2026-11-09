# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FederationRequestFlushBatch do
  it 'claims a batch key only once and selects claims older than the retention period as expired' do
    expect(described_class.claim!('batch-1')).to be true
    expect(described_class.claim!('batch-1')).to be false
    expect(described_class.claim!('batch-2')).to be true

    expired = described_class.create!(batch_key: 'old', created_at: (described_class::RETENTION_PERIOD + 1.day).ago)
    recent = described_class.create!(batch_key: 'recent', created_at: 1.day.ago)

    expect(described_class.expired).to include(expired)
    expect(described_class.expired).to_not include(recent)
  end
end
