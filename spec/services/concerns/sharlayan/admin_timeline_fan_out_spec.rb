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

  def published_events_for(status, update: false)
    calls = []
    allow(redis).to receive(:publish).and_wrap_original do |original, channel, payload|
      calls << [channel, JSON.parse(payload)]
      original.call(channel, payload)
    end

    service.call(status, update: update)
    calls
  end

  def published_channels_for(status, update: false)
    published_events_for(status, update: update).map(&:first)
  end

  it 'publishes public posts to the management timeline' do
    status = Fabricate(:status, account: account, visibility: :public, local_only: false)

    expect(published_channels_for(status)).to include('timeline:admin')
    expect(published_channels_for(status)).to include('timeline:admin:owner')
  end

  it 'publishes local-only restricted posts' do
    status = Fabricate(:status, account: account, visibility: :private, local_only: true)

    expect(published_channels_for(status)).to include('timeline:admin')
    expect(published_channels_for(status)).to include('timeline:admin:owner')
  end

  it 'publishes posts to management streams for accounts followed by the author' do
    leader = Fabricate(:account, username: 'leader')
    Fabricate(:follow, account: account, target_account: leader)
    status = Fabricate(:status, account: account, visibility: :private, local_only: true)

    expect(published_channels_for(status)).to include("timeline:admin:followers:#{leader.id}")
  end

  it 'does not publish federated restricted posts' do
    %i(direct private unlisted limited).each do |visibility|
      status = Fabricate(:status, account: account, visibility: visibility, local_only: false)

      expect(published_channels_for(status)).to_not include('timeline:admin', 'timeline:admin:owner')
    end
  end

  it 'does not publish cached posts authored by remote accounts' do
    remote = Fabricate(:account, domain: 'remote.example', username: 'remote-poster')
    status = Fabricate(:status, account: remote, visibility: :public, local_only: false)

    expect(published_channels_for(status)).to_not include('timeline:admin', 'timeline:admin:owner')
  end

  context 'with an owner conversation' do
    let(:owner_role) { UserRole.find_by(name: 'Owner') }
    let(:owner) { Fabricate(:user, role: owner_role).account }

    it 'publishes an owner-authored direct post only to the owner stream' do
      status = Fabricate(:status, account: owner, visibility: :direct, local_only: true)

      expect(published_channels_for(status))
        .to include('timeline:admin:owner')
        .and not_include('timeline:admin')
    end

    it 'publishes a direct post mentioning an owner only to the owner stream' do
      leader = Fabricate(:account, username: 'leader')
      Fabricate(:follow, account: account, target_account: leader)
      status = Fabricate(:status, account: account, visibility: :direct, local_only: true)
      Fabricate(:mention, status: status, account: owner)

      expect(published_channels_for(status))
        .to include('timeline:admin:owner')
        .and not_include('timeline:admin')
        .and not_include("timeline:admin:followers:#{leader.id}")
    end

    it 'keeps an owner-authored public post on the regular stream' do
      status = Fabricate(:status, account: owner, visibility: :public, local_only: true)

      expect(published_channels_for(status))
        .to include('timeline:admin')
        .and include('timeline:admin:owner')
    end

    it 'revokes the regular stream copy when an update becomes an owner conversation' do
      status = Fabricate(:status, account: owner, visibility: :direct, local_only: true)

      events = published_events_for(status, update: true)

      expect(events).to include(
        ['timeline:admin', { 'event' => 'delete', 'payload' => status.id.to_s }],
        ['timeline:admin:owner', hash_including('event' => 'status.update')]
      )
    end
  end

  describe Sharlayan::AdminTimelineFanOut::Remove do
    subject(:remove_service) { remove_service_class.new }

    let(:remove_service_class) do
      Class.new do
        include Redisable

        def call(status, **)
          @payload = { event: :delete, payload: status.id.to_s }.to_json
        end

        prepend Sharlayan::AdminTimelineFanOut::Remove
      end
    end

    it 'publishes removals to both isolated streams' do
      status = Fabricate(:status, account: account, visibility: :direct, local_only: true)
      channels = []
      allow(redis).to receive(:publish) { |channel, _payload| channels << channel }

      remove_service.call(status)

      expect(channels).to contain_exactly('timeline:admin', 'timeline:admin:owner')
    end
  end
end
