# frozen_string_literal: true

module Api::ClipNotesRateLimit
  extend ActiveSupport::Concern

  RateLimitIdentity = Struct.new(:id)

  private

  def record_clip_notes_request!
    limiter = RateLimiter.new(clip_notes_rate_limit_identity, family: :clip_notes)
    limiter.record!
    apply_clip_notes_rate_limit_headers(limiter)
  rescue Mastodon::RateLimitExceededError
    apply_clip_notes_rate_limit_headers(limiter, exceeded: true)
    raise
  end

  def clip_notes_rate_limit_identity
    current_account || RateLimitIdentity.new("ip:#{normalized_clip_notes_ip}")
  end

  def normalized_clip_notes_ip
    @normalized_clip_notes_ip ||= begin
      ip = IPAddr.new(request.remote_ip)
      ip = ip.mask(64) if ip.ipv6?
      ip.to_s
    end
  end

  def apply_clip_notes_rate_limit_headers(limiter, exceeded: false)
    headers = limiter.to_headers
    response.headers.merge!(headers)
    return unless exceeded

    response.headers['Retry-After'] = [(Time.iso8601(headers['X-RateLimit-Reset']) - Time.now.utc).ceil, 1].max.to_s
    response.headers['Cache-Control'] = 'private, no-store'
  end
end
