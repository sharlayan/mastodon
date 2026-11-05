# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::FederationRequestTracker do
  before { travel_to(Time.utc(2026, 8, 4, 12, 30)) }

  describe '.normalize_domain' do
    it 'extracts and normalizes the host from inbox URLs and bare domains' do
      expect(described_class.normalize_domain('https://Example.COM/inbox')).to eq('example.com')
      expect(described_class.normalize_domain('example.com')).to eq('example.com')
      expect(described_class.normalize_domain('')).to be_nil
    end
  end

  describe '.enabled?' do
    it 'follows the admin setting' do
      expect(described_class).to be_enabled

      Setting.federation_request_statistics_enabled = false
      expect(described_class).to_not be_enabled
    ensure
      Setting.federation_request_statistics_enabled = true
    end

    it 'stays off in roleplay mode even when the admin setting is on' do
      ClimateControl.modify OC_ROLEPLAY_OPTION: 'true' do
        expect(described_class).to_not be_enabled
      end
    end
  end

  describe 'when disabled' do
    it 'buffers nothing while the admin setting is off' do
      Setting.federation_request_statistics_enabled = false

      described_class.track_deliver_success!('example.com')
      described_class.track_inbox_received!('example.com')

      Setting.federation_request_statistics_enabled = true
      expect(described_class.flush!).to eq(0)
      expect(FederationRequestStatistic.count).to eq(0)
    ensure
      Setting.federation_request_statistics_enabled = true
    end

    it 'buffers nothing in roleplay mode' do
      ClimateControl.modify OC_ROLEPLAY_OPTION: 'true' do
        described_class.track_deliver_failure!('example.com')
      end

      expect(described_class.flush!).to eq(0)
      expect(FederationRequestStatistic.count).to eq(0)
    end
  end

  describe '.flush!' do
    it 'accumulates buffered counters into hourly rows per domain' do
      described_class.track_deliver_success!('https://example.com/inbox')
      described_class.track_deliver_success!('https://example.com/users/alice/inbox')
      described_class.track_deliver_failure!('https://example.com/inbox')
      described_class.track_inbox_received!('other.example')

      expect(described_class.flush!).to eq(2)

      record = FederationRequestStatistic.find_by(domain: 'example.com')
      expect(record.bucket_at).to eq(Time.utc(2026, 8, 4, 12))
      expect(record.deliver_succeeded_count).to eq(2)
      expect(record.deliver_failed_count).to eq(1)
      expect(record.inbox_received_count).to eq(0)

      other = FederationRequestStatistic.find_by(domain: 'other.example')
      expect(other.inbox_received_count).to eq(1)
    end

    it 'adds to an existing bucket row instead of replacing it' do
      described_class.track_deliver_success!('example.com')
      described_class.flush!
      described_class.track_deliver_success!('example.com')
      described_class.flush!

      expect(FederationRequestStatistic.find_by(domain: 'example.com').deliver_succeeded_count).to eq(2)
    end

    it 'drains the buffer so repeated flushes do not double count' do
      described_class.track_inbox_received!('example.com')
      described_class.flush!

      expect(described_class.flush!).to eq(0)
      expect(FederationRequestStatistic.find_by(domain: 'example.com').inbox_received_count).to eq(1)
    end

    it 'flushes buckets left behind by earlier hours within the flush window' do
      travel_to(Time.utc(2026, 8, 4, 9, 5)) { described_class.track_deliver_failure!('example.com') }

      described_class.flush!

      expect(FederationRequestStatistic.find_by(domain: 'example.com').bucket_at).to eq(Time.utc(2026, 8, 4, 9))
    end

    it 'keeps buffered observations available after the database write fails' do
      described_class.track_deliver_success!('example.com')
      allow(FederationRequestStatistic).to receive(:accumulate!).and_raise(ActiveRecord::StatementInvalid, 'database unavailable')

      expect { described_class.flush! }.to raise_error(ActiveRecord::StatementInvalid)

      allow(FederationRequestStatistic).to receive(:accumulate!).and_call_original
      described_class.flush!

      expect(FederationRequestStatistic.find_by!(domain: 'example.com').deliver_succeeded_count).to eq(1)
      expect(described_class.flush!).to eq(0)
    end

    it 'preserves new observations received while a failed batch is waiting to be retried' do
      described_class.track_deliver_success!('example.com')
      allow(FederationRequestStatistic).to receive(:accumulate!) do
        described_class.track_deliver_failure!('example.com')
        described_class.track_inbox_received!('other.example')
        raise ActiveRecord::StatementInvalid, 'database unavailable'
      end

      expect { described_class.flush! }.to raise_error(ActiveRecord::StatementInvalid)

      allow(FederationRequestStatistic).to receive(:accumulate!).and_call_original
      described_class.flush!
      described_class.flush!

      expect(FederationRequestStatistic.find_by!(domain: 'example.com'))
        .to have_attributes(deliver_succeeded_count: 1, deliver_failed_count: 1)
      expect(FederationRequestStatistic.find_by!(domain: 'other.example').inbox_received_count).to eq(1)
      expect(described_class.flush!).to eq(0)
    end

    it 'does not count a batch twice when another flush runs while its database write is in progress' do
      described_class.track_deliver_success!('example.com')
      concurrent_flush_ran = false
      allow(FederationRequestStatistic).to receive(:accumulate!).and_wrap_original do |original, rows|
        unless concurrent_flush_ran
          concurrent_flush_ran = true
          described_class.track_deliver_success!('example.com')
          described_class.flush!
        end

        original.call(rows)
      end

      described_class.flush!
      described_class.flush!

      expect(FederationRequestStatistic.find_by!(domain: 'example.com').deliver_succeeded_count).to eq(2)
      expect(described_class.flush!).to eq(0)
    end

    it 'keeps observations buffered when another flusher holds the bucket lock' do
      described_class.track_deliver_success!('example.com')
      allow(RedisLock).to receive(:acquire).and_yield(instance_double(RedisLock, acquired?: false))

      expect(described_class.flush!).to eq(0)
      expect(FederationRequestStatistic.count).to eq(0)

      allow(RedisLock).to receive(:acquire).and_call_original
      described_class.flush!

      expect(FederationRequestStatistic.find_by!(domain: 'example.com').deliver_succeeded_count).to eq(1)
    end

    it 'propagates Redis command failures other than an absent source buffer' do
      allow(redis).to receive(:rename).and_raise(Redis::CommandError, 'READONLY You cannot write against a read only replica')

      expect { described_class.flush! }.to raise_error(Redis::CommandError, /READONLY/)
    end
  end
end
