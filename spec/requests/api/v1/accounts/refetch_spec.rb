# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'POST /api/v1/accounts/:id/refetch' do
  subject { post "/api/v1/accounts/#{account.id}/refetch", headers: headers }

  include_context 'with API authentication'

  let(:scopes) { 'write:accounts' }

  context 'with a remote account' do
    let(:account) { Fabricate(:account, domain: 'example.org') }

    it 'queues a remote account refresh worker' do
      subject

      expect(response).to have_http_status(200)
      expect(RemoteAccountRefreshWorker).to have_enqueued_sidekiq_job(account.id)
    end

    it_behaves_like 'forbidden for wrong scope', 'read:accounts'
  end

  context 'with a local account' do
    let(:account) { Fabricate(:account, domain: nil) }

    it 'returns 422 error' do
      subject

      expect(response).to have_http_status(422)
    end
  end

  context 'when rate limited' do
    let(:account) { Fabricate(:account, domain: 'example.org') }

    before do
      rate_limiter = RateLimiter.new(user.account, family: :account_refetch)
      10.times { rate_limiter.record! }
    end

    it 'returns 429 error' do
      subject

      expect(response).to have_http_status(429)
    end
  end

  context 'when target rate limited' do
    let(:account) { Fabricate(:account, domain: 'example.org') }

    before do
      key = "rate_limit:refetch_target:#{account.id}:#{Time.now.to_i / 1.hour.to_i}"
      Redis.current.set(key, 2)
      Redis.current.expire(key, 1.hour.to_i)
    end

    it 'returns 429 error' do
      subject

      expect(response).to have_http_status(429)
    end
  end

  context 'when user has administrator role' do
    let(:account) { Fabricate(:account, domain: 'example.org') }
    let(:user) { Fabricate(:user, role: UserRole.find_by(name: 'Admin')) }

    before do
      rate_limiter = RateLimiter.new(user.account, family: :account_refetch)
      10.times { rate_limiter.record! }
    end

    it 'bypasses rate limit' do
      subject

      expect(response).to have_http_status(200)
      expect(RemoteAccountRefreshWorker).to have_enqueued_sidekiq_job(account.id)
    end
  end
end
