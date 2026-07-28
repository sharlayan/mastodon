# frozen_string_literal: true

module Api::AnonymousPageViewLimit
  extend ActiveSupport::Concern

  RateLimitIdentity = Struct.new(:id)

  private

  def anonymous_page_view_limit_exceeded?(page)
    return false if current_account

    page_limiter = RateLimiter.new(RateLimitIdentity.new("#{normalized_page_view_ip}:#{page.id}"), family: :anonymous_page_views)
    global_limiter = RateLimiter.new(RateLimitIdentity.new(normalized_page_view_ip), family: :anonymous_pages)

    active_limiter = page_limiter
    page_limiter.record!
    page_limit_recorded = true
    active_limiter = global_limiter
    global_limiter.record!

    false
  rescue Mastodon::RateLimitExceededError
    page_limiter.rollback! if page_limit_recorded && active_limiter == global_limiter
    apply_anonymous_page_rate_limit_headers(active_limiter, exceeded: true)
    true
  end

  def normalized_page_view_ip
    @normalized_page_view_ip ||= begin
      ip = IPAddr.new(request.remote_ip)
      ip = ip.mask(64) if ip.ipv6?
      ip.to_s
    end
  end

  def apply_anonymous_page_rate_limit_headers(limiter, exceeded: false)
    headers = limiter.to_headers
    response.headers.merge!(headers)
    return unless exceeded

    response.headers['Retry-After'] = [(Time.iso8601(headers['X-RateLimit-Reset']) - Time.now.utc).ceil, 1].max.to_s
    response.headers['Cache-Control'] = 'private, no-store'
  end
end
