# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RemoteMediaDownloadBudget do
  subject { described_class.new(byte_limit: 100, time_limit: 5, clock: clock) }

  let(:now) { 10.0 }
  let(:clock) { -> { now } }

  it 'limits a file to the remaining byte budget' do
    expect(subject.size_limit(200)).to eq(100)

    subject.consume(60)

    expect(subject.size_limit(200)).to eq(40)
  end

  it 'becomes unavailable when the byte budget is exhausted' do
    subject.consume(100)

    expect(subject).to_not be_available
  end

  it 'charges stored bytes for a completed download' do
    subject.charge_download(80, 'https://remote.example/file', 30)

    expect(subject.size_limit(200)).to eq(70)
  end

  it 'charges the allowance for a download that left no file' do
    subject.charge_download(80, 'https://remote.example/file', nil)

    expect(subject.size_limit(200)).to eq(20)
  end

  it 'does not charge when no download was attempted' do
    subject.charge_download(80, '', nil)

    expect(subject.size_limit(200)).to eq(100)
  end

  it 'becomes unavailable when the time budget is exhausted' do
    allow(clock).to receive(:call).and_return(10.0, 15.0)

    expect(subject).to_not be_available
  end
end
