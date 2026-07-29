# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PageViewTracker do
  subject(:tracker) { described_class.new(page, account: account, request: request) }

  let(:page) { Fabricate(:page) }
  let(:account) { nil }
  let(:request) { instance_double(ActionDispatch::Request, remote_ip: '192.0.2.10', user_agent: 'Mozilla/5.0') }

  it 'counts an anonymous visitor once during the cache window', :aggregate_failures do
    expect(tracker.call).to be true
    expect(tracker.call).to be false

    expect(page.reload.anonymous_views_count).to eq(1)
    expect(page.authenticated_views_count).to eq(0)
    ttl = RedisConnection.with { |redis| redis.ttl(redis.keys("page_view:v1:#{page.id}:visitor:*").first) }
    expect(ttl).to be_between(1, described_class::ANONYMOUS_DEDUPLICATION_TTL)
  end

  context 'with an authenticated viewer' do
    let(:account) { Fabricate(:account) }

    it 'keeps the authenticated counter separate and deduplicates refreshes', :aggregate_failures do
      2.times { tracker.call }

      expect(page.reload.authenticated_views_count).to eq(1)
      expect(page.anonymous_views_count).to eq(0)
      expect(page.views_count).to eq(1)
    end
  end

  context 'when the viewer owns the page' do
    let(:account) { page.account }

    it 'does not count the view' do
      expect { tracker.call }.to_not(change { page.reload.views_count })
    end
  end

  context 'when the request is from a crawler' do
    let(:request) { instance_double(ActionDispatch::Request, remote_ip: '192.0.2.10', user_agent: 'Googlebot/2.1') }

    it 'does not count the view' do
      expect { tracker.call }.to_not(change { page.reload.views_count })
    end
  end
end
