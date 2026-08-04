# frozen_string_literal: true

class Sharlayan::FederationRequestTracker
  extend Redisable

  KEY_PREFIX = 'sharlayan:federation_requests'
  BUFFER_EXPIRE_AFTER = 2.days.seconds
  FLUSH_WINDOW = 6.hours
  FIELD_SEPARATOR = '|'
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
      return 0 unless enabled?

      bucket_times(now).sum { |bucket_at| flush_bucket(bucket_at) }
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

    def flush_bucket(bucket_at)
      key = key_at(bucket_at)
      staging_key = "#{key}:flush:#{SecureRandom.hex(8)}"

      begin
        redis.rename(key, staging_key)
      rescue Redis::CommandError
        return 0
      end

      counters = redis.hgetall(staging_key)
      redis.del(staging_key)

      rows = build_rows(bucket_at, counters)
      FederationRequestStatistic.accumulate!(rows)
      rows.size
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
