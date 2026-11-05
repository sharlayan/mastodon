# frozen_string_literal: true

class Sharlayan::FederationRequestTracker
  extend Redisable

  KEY_PREFIX = 'sharlayan:federation_requests'
  BUFFER_EXPIRE_AFTER = 2.days.seconds
  FLUSH_WINDOW = 6.hours
  FLUSH_LOCK_TTL = 15.minutes.to_i
  FIELD_SEPARATOR = '|'
  PENDING_KEY = "#{KEY_PREFIX}:pending".freeze
  STAGING_KEY_PATTERN = /\A#{Regexp.escape(KEY_PREFIX)}:(\d+):flush:\h+\z/
  STAGE_SCRIPT = <<~LUA
    if redis.call('EXISTS', KEYS[1]) == 0 then
      return 0
    end
    redis.call('RENAME', KEYS[1], KEYS[2])
    redis.call('PERSIST', KEYS[2])
    redis.call('SADD', KEYS[3], KEYS[2])
    return 1
  LUA
  METRICS = {
    deliver_succeeded: :deliver_succeeded_count,
    deliver_failed: :deliver_failed_count,
    inbox_received: :inbox_received_count,
  }.freeze

  class << self
    def enabled?
      return false if RoleplayModeHelper.roleplay_mode?

      Setting.federation_request_statistics_enabled
    end

    def track_deliver_success!(url_or_domain, at_time: Time.now.utc)
      increment(:deliver_succeeded, url_or_domain, at_time)
    end

    def track_deliver_failure!(url_or_domain, at_time: Time.now.utc)
      increment(:deliver_failed, url_or_domain, at_time)
    end

    def track_inbox_received!(url_or_domain, at_time: Time.now.utc)
      increment(:inbox_received, url_or_domain, at_time)
    end

    def flush!(now: Time.now.utc)
      bucket_times(now).each { |bucket_at| stage_bucket(bucket_at) } if enabled?
      redis.smembers(PENDING_KEY).sum { |staging_key| flush_staged(staging_key) }
    end

    def normalize_domain(url_or_domain)
      value = url_or_domain.to_s.strip
      return if value.empty?

      host = if value.start_with?('https://', 'http://')
               Addressable::URI.parse(value).normalized_host
             else
               Addressable::URI.parse("https://#{value}").normalized_host
             end

      host.presence
    rescue Addressable::URI::InvalidURIError
      nil
    end

    private

    def increment(metric, url_or_domain, at_time)
      return unless enabled?

      domain = normalize_domain(url_or_domain)
      return if domain.nil? || domain.include?(FIELD_SEPARATOR)

      key = key_at(at_time)

      redis.pipelined do |pipeline|
        pipeline.hincrby(key, "#{domain}#{FIELD_SEPARATOR}#{metric}", 1)
        pipeline.expire(key, BUFFER_EXPIRE_AFTER)
      end
    end

    def stage_bucket(bucket_at)
      key = key_at(bucket_at)

      [key, "#{key}:flush"].each do |source_key|
        redis.eval(STAGE_SCRIPT, keys: [source_key, "#{key}:flush:#{SecureRandom.hex(8)}", PENDING_KEY])
      end
    end

    def flush_staged(staging_key)
      result = 0

      with_redis do |connection|
        RedisLock.acquire(redis: connection, key: "lock:#{staging_key}", autorelease: FLUSH_LOCK_TTL, retry: false) do |lock|
          result = apply_staged(staging_key) if lock.acquired?
        end
      end

      result
    end

    def apply_staged(staging_key)
      bucket_at = staged_bucket_at(staging_key)
      rows = bucket_at ? build_rows(bucket_at, redis.hgetall(staging_key)) : []

      applied = FederationRequestStatistic.transaction do
        next false unless FederationRequestFlushBatch.claim!(staging_key)

        FederationRequestStatistic.accumulate!(rows)
        true
      end

      discard_staged(staging_key)
      applied ? rows.size : 0
    end

    def discard_staged(staging_key)
      redis.multi do |transaction|
        transaction.del(staging_key)
        transaction.srem(PENDING_KEY, staging_key)
      end
    end

    def staged_bucket_at(staging_key)
      match = STAGING_KEY_PATTERN.match(staging_key)
      Time.at(match[1].to_i).utc if match
    end

    def build_rows(bucket_at, counters)
      accumulator = {}

      counters.each do |field, value|
        domain, metric = field.split(FIELD_SEPARATOR, 2)
        column = METRICS[metric&.to_sym]
        next if domain.blank? || column.nil?

        columns = (accumulator[domain] ||= METRICS.values.index_with { 0 })
        columns[column] += value.to_i if column
      end

      accumulator.map { |domain, columns| columns.merge(domain: domain, bucket_at: bucket_at) }
    end

    def bucket_times(now)
      current = now.utc.beginning_of_hour
      steps = (FLUSH_WINDOW / 1.hour).to_i

      Array.new(steps + 1) { |index| current - (index * 1.hour) }
    end

    def key_at(at_time)
      "#{KEY_PREFIX}:#{at_time.utc.beginning_of_hour.to_i}"
    end
  end
end
