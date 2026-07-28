# frozen_string_literal: true

module Api::AccountRateLimit
  extend ActiveSupport::Concern

  private

  def enforce_account_rate_limit!(family)
    limiter = RateLimiter.new(current_account, family: family)
    limiter.record!
    apply_account_rate_limit_headers(limiter)
  rescue Mastodon::RateLimitExceededError
    apply_account_rate_limit_headers(limiter, exceeded: true)
    raise
  end

  def apply_account_rate_limit_headers(limiter, exceeded: false)
    headers = limiter.to_headers
    response.headers.merge!(headers)
    return unless exceeded

    response.headers['Retry-After'] = [(Time.iso8601(headers['X-RateLimit-Reset']) - Time.now.utc).ceil, 1].max.to_s
    response.headers['Cache-Control'] = 'private, no-store'
  end
end
