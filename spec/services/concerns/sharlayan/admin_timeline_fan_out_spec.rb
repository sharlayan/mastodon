# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::AdminTimelineFanOut do
  subject(:service) { service_class.new }

  let(:service_class) do
    Class.new(FanOutOnWriteService) do
      prepend Sharlayan::AdminTimelineFanOut::FanOut
    end
  end

  let(:account) { Fabricate(:account) }

  def publish_calls_for(status)
    calls = []
    allow(redis).to receive(:publish).and_wrap_original do |original, channel, payload|
      calls << channel
      original.call(channel, payload)
    end

    service.call(status, update: false)
    calls.count('timeline:admin')
  end

  it 'publishes public posts to the management timeline' do
    status = Fabricate(:status, account: account, visibility: :public, local_only: false)

    expect(publish_calls_for(status)).to eq(1)
  end

  it 'publishes local-only restricted posts' do
    status = Fabricate(:status, account: account, visibility: :private, local_only: true)

    expect(publish_calls_for(status)).to eq(1)
  end

  it 'does not publish federated restricted posts' do
    %i(direct private unlisted limited).each do |visibility|
      status = Fabricate(:status, account: account, visibility: visibility, local_only: false)

      expect(publish_calls_for(status)).to eq(0)
    end
  end

  it 'does not publish cached posts authored by remote accounts' do
    remote = Fabricate(:account, domain: 'remote.example', username: 'remote-poster')
    status = Fabricate(:status, account: remote, visibility: :public, local_only: false)

    expect(publish_calls_for(status)).to eq(0)
  end
end
