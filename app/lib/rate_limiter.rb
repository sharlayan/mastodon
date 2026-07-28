# frozen_string_literal: true

class RateLimiter
  include Redisable

  INCREMENT_SCRIPT = <<~LUA
    local count = redis.call('INCR', KEYS[1])
    if count == 1 then
      redis.call('EXPIRE', KEYS[1], ARGV[1])
    end
    return count
  LUA

  ROLLBACK_SCRIPT = <<~LUA
    local count = redis.call('GET', KEYS[1])
    if count and tonumber(count) > 0 then
      return redis.call('DECR', KEYS[1])
    end
    return 0
  LUA

  FAMILIES = {
    follows: {
      limit: 1000,
      period: 24.hours.freeze,
    }.freeze,

    statuses: {
      limit: 1000,
      period: 3.hours.freeze,
    }.freeze,

    reports: {
      limit: 400,
      period: 24.hours.freeze,
    }.freeze,

    misskey_compat_api: {
      limit: 300,
      period: 5.minutes.freeze,
    }.freeze,

    misskey_compat_signin: {
      limit: 25,
      period: 5.minutes.freeze,
    }.freeze,

    misskey_compat_ap_get: {
      limit: 30,
      period: 1.hour.freeze,
    }.freeze,

    drive_uploads: {
      limit: 100,
      period: 30.minutes.freeze,
    }.freeze,

    account_refetch: {
      limit: 10,
      period: 1.hour.freeze,
    }.freeze,

    misskey_users_show: {
      limit: 100,
      period: 1.hour.freeze,
    }.freeze,

    implicit_quotes: {
      limit: 30,
      period: 5.minutes.freeze,
    }.freeze,

    anonymous_page_views: {
      limit: 60,
      period: 10.minutes.freeze,
    }.freeze,

    anonymous_pages: {
      limit: 600,
      period: 10.minutes.freeze,
    }.freeze,

    status_drafts: {
      limit: 120,
      period: 5.minutes.freeze,
    }.freeze,

    misskey_registry: {
      limit: 120,
      period: 5.minutes.freeze,
    }.freeze,

    clip_notes: {
      limit: 120,
      period: 5.minutes.freeze,
    }.freeze,

    status_reactions: {
      limit: 120,
      period: 5.minutes.freeze,
    }.freeze,

    misskey_hashtags: {
      limit: 120,
      period: 5.minutes.freeze,
    }.freeze,
  }.freeze

  def initialize(by, options = {})
    @by     = by
    @family = options[:family]
    @limit  = FAMILIES[@family][:limit]
    @period = FAMILIES[@family][:period].to_i
  end

  def record!
    ttl = (@period - (last_epoch_time % @period) + 1).to_i
    count = redis.eval(INCREMENT_SCRIPT, keys: [key], argv: [ttl]).to_i
    return if count <= @limit

    rollback!
    raise Mastodon::RateLimitExceededError
  end

  def rollback!
    redis.eval(ROLLBACK_SCRIPT, keys: [key])
  end

  def to_headers(now = Time.now.utc)
    {
      'X-RateLimit-Limit' => @limit.to_s,
      'X-RateLimit-Remaining' => (@limit - (redis.get(key) || 0).to_i).to_s,
      'X-RateLimit-Reset' => (now + (@period - (now.to_i % @period))).iso8601(6),
    }
  end

  private

  def key
    @key ||= "rate_limit:#{@by.id}:#{@family}:#{(last_epoch_time / @period).to_i}"
  end

  def last_epoch_time
    @last_epoch_time ||= Time.now.to_i
  end
end
