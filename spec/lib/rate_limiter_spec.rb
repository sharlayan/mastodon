# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RateLimiter do
  let(:identity) { Struct.new(:id).new('rate-limiter-spec') }
  let(:family) { :misskey_registry }
  let(:limit) { described_class::FAMILIES[family][:limit] }
  let(:limiter) { described_class.new(identity, family: family) }

  it 'allows exactly the configured number of records' do
    limit.times { limiter.record! }

    expect { limiter.record! }.to raise_error(Mastodon::RateLimitExceededError)
    expect(limiter.to_headers['X-RateLimit-Remaining']).to eq('0')
  end

  it 'sets an expiry on a newly-created window' do
    limiter.record!
    key = redis.keys('rate_limit:rate-limiter-spec:misskey_registry:*').sole

    expect(redis.ttl(key)).to be_between(1, described_class::FAMILIES[family][:period].to_i + 1)
  end

  it 'does not recreate an expired key when rolling back' do
    limiter.record!
    key = redis.keys('rate_limit:rate-limiter-spec:misskey_registry:*').sole
    redis.del(key)

    limiter.rollback!

    expect(redis.get(key)).to be_nil
  end
end
