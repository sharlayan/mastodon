# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::FederationAggregationRunner do
  let(:successful_runner_class) do
    Class.new(described_class) do
      def with_redis_lock(*)
        yield
      end
    end
  end

  let(:unavailable_runner_class) do
    Class.new(described_class) do
      def with_redis_lock(*)
        nil
      end
    end
  end

  it 'returns the aggregation result while holding the shared lock' do
    expect(successful_runner_class.new.call { 7 }).to eq(7)
  end

  it 'runs an aggregation through the real Redis lock' do
    expect(described_class.call { 7 }).to eq(7)
  end

  it 'returns zero without running the aggregation when the lock is unavailable' do
    aggregation = instance_spy(Proc)

    expect(unavailable_runner_class.new.call { aggregation.call }).to eq(0)
    expect(aggregation).to_not have_received(:call)
  end
end
