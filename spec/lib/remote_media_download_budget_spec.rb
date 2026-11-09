# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RemoteMediaDownloadBudget do
  subject { described_class.new(byte_limit: 100, time_limit: 5, clock: clock) }

  let(:now) { 10.0 }
  let(:clock) { -> { now } }

  def new_budget
    described_class.new(byte_limit: 100, time_limit: 5, clock: clock)
  end

  it 'limits a file to the remaining byte budget and becomes unavailable when it is exhausted' do
    expect(subject.size_limit(200)).to eq(100)

    subject.consume(60)

    expect(subject.size_limit(200)).to eq(40)
    expect(subject).to be_available

    subject.consume(40)

    expect(subject).to_not be_available
  end

  it 'charges stored bytes, the allowance for a download that left no file, and nothing when no download was attempted' do
    completed = new_budget
    discarded = new_budget
    skipped = new_budget

    completed.charge_download(80, 'https://remote.example/file', 30)
    discarded.charge_download(80, 'https://remote.example/file', nil)
    skipped.charge_download(80, '', nil)

    expect(completed.size_limit(200)).to eq(70)
    expect(discarded.size_limit(200)).to eq(20)
    expect(skipped.size_limit(200)).to eq(100)
  end

  it 'becomes unavailable when the time budget is exhausted' do
    allow(clock).to receive(:call).and_return(10.0, 15.0)

    expect(subject).to_not be_available
  end
end
