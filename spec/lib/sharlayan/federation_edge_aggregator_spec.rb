# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::FederationEdgeAggregator do
  let(:local)  { Fabricate(:account, domain: nil) }
  let(:remote_b) { Fabricate(:account, domain: 'b.example') }
  let(:remote_d) { Fabricate(:account, domain: 'd.example') }

  def edge(source, target)
    FederationInstanceEdge.find_by(source_domain: source, target_domain: target)
  end

  describe '.call' do
    before do
      Setting.federation_instance_edges_enabled = true
      allow(Sharlayan::FederationAggregationRunner).to receive(:call).and_yield
    end

    after do
      Setting.federation_instance_edges_enabled = false
    end

    it 'records a remote-to-remote edge observed only through a boost' do
      original = Fabricate(:status, account: remote_d)
      Fabricate(:status, account: remote_b, reblog: original)

      expect(described_class.call).to eq(1)

      expect(edge('b.example', 'd.example'))
        .to have_attributes(reblogs_count: 1, replies_count: 0, quotes_count: 0)
    end

    it 'keeps direction, so a boost the other way is a separate edge' do
      Fabricate(:status, account: remote_b, reblog: Fabricate(:status, account: remote_d))
      Fabricate(:status, account: remote_d, reblog: Fabricate(:status, account: remote_b))

      described_class.call

      expect(edge('b.example', 'd.example').reblogs_count).to eq(1)
      expect(edge('d.example', 'b.example').reblogs_count).to eq(1)
    end

    it 'sums boosts, replies and accepted quotes into one edge row with a seen range' do
      travel_to(Time.utc(2026, 8, 1, 9)) { Fabricate(:status, account: remote_b, reblog: Fabricate(:status, account: remote_d)) }
      travel_to(Time.utc(2026, 8, 2, 9)) { Fabricate(:status, account: remote_b, thread: Fabricate(:status, account: remote_d)) }
      travel_to(Time.utc(2026, 8, 3, 9)) { Fabricate(:quote, account: remote_b, quoted_account: remote_d, status: Fabricate(:status, account: remote_b), quoted_status: Fabricate(:status, account: remote_d), state: :accepted) }

      described_class.call

      expect(edge('b.example', 'd.example'))
        .to have_attributes(
          reblogs_count: 1,
          replies_count: 1,
          quotes_count: 1,
          first_seen_at: Time.utc(2026, 8, 1, 9),
          last_seen_at: Time.utc(2026, 8, 3, 9)
        )
    end

    it 'represents our own server as a null domain on either side' do
      Fabricate(:status, account: local, reblog: Fabricate(:status, account: remote_b))
      Fabricate(:status, account: remote_b, reblog: Fabricate(:status, account: local))

      described_class.call

      expect(edge(nil, 'b.example').reblogs_count).to eq(1)
      expect(edge('b.example', nil).reblogs_count).to eq(1)
    end

    it 'skips within-instance activity, which is not a federation edge' do
      other_local = Fabricate(:account, domain: nil)
      other_remote = Fabricate(:account, domain: 'b.example')
      Fabricate(:status, account: local, reblog: Fabricate(:status, account: other_local))
      Fabricate(:status, account: remote_b, reblog: Fabricate(:status, account: other_remote))

      described_class.call

      expect(FederationInstanceEdge.count).to eq(0)
    end

    it 'ignores quotes that were never accepted' do
      Fabricate(:quote, account: remote_b, quoted_account: remote_d, status: Fabricate(:status, account: remote_b), quoted_status: Fabricate(:status, account: remote_d), state: :pending)

      described_class.call

      expect(FederationInstanceEdge.count).to eq(0)
    end

    it 'replaces the previous snapshot instead of accumulating across runs' do
      Fabricate(:status, account: remote_b, reblog: Fabricate(:status, account: remote_d))
      described_class.call
      described_class.call

      expect(edge('b.example', 'd.example').reblogs_count).to eq(1)
    end

    it 'drops edges whose underlying posts are gone' do
      reblog = Fabricate(:status, account: remote_b, reblog: Fabricate(:status, account: remote_d))
      described_class.call
      reblog.discard

      described_class.call

      expect(edge('b.example', 'd.example')).to be_nil
    end

    it 'does nothing while the admin setting is off' do
      Fabricate(:status, account: remote_b, reblog: Fabricate(:status, account: remote_d))
      Setting.federation_instance_edges_enabled = false

      expect(described_class.call).to eq(0)
      expect(FederationInstanceEdge.count).to eq(0)
    end

    it 'runs the snapshot through the shared federation aggregation runner' do
      described_class.call

      expect(Sharlayan::FederationAggregationRunner).to have_received(:call)
    end

    it 'instruments the snapshot result for production measurements' do
      events = []
      callback = ->(*args) { events << ActiveSupport::Notifications::Event.new(*args) }

      ActiveSupport::Notifications.subscribed(callback, 'federation_edge_snapshot.sharlayan') do
        Fabricate(:status, account: remote_b, reblog: Fabricate(:status, account: remote_d))
        described_class.call
      end

      expect(events.one?).to be true
      expect(events.first.payload[:affected_rows]).to eq(1)
      expect(events.first.duration).to be >= 0
    end

    it 'does nothing in roleplay mode' do
      Fabricate(:status, account: remote_b, reblog: Fabricate(:status, account: remote_d))

      ClimateControl.modify OC_ROLEPLAY_OPTION: 'true' do
        expect(described_class.call).to eq(0)
      end

      expect(FederationInstanceEdge.count).to eq(0)
    end
  end
end
