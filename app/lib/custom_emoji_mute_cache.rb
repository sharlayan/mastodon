# frozen_string_literal: true

class CustomEmojiMuteCache
  KEY_PREFIX = 'custom_emoji_mutes:v1'
  MAX_RULES = CustomEmojiMute::PER_ACCOUNT_LIMIT

  class << self
    def read(account_id)
      return [] if account_id.blank?

      raw = RedisConnection.with { |redis| redis.get(key(account_id)) }
      return [] if raw.blank?

      parsed = JSON.parse(raw)
      return [] unless parsed.is_a?(Array)

      parsed.first(MAX_RULES).filter_map do |rule|
        next unless rule.is_a?(Hash)

        prefix = rule['prefix'].to_s.strip.downcase
        next if prefix.blank?

        {
          'prefix' => prefix,
          'domain' => rule['domain'].to_s.strip.downcase,
        }
      end
    rescue JSON::ParserError, Redis::BaseError
      []
    end

    def write(account_id)
      rules = CustomEmojiMute
        .for_account(account_id)
        .where.not(prefix: '')
        .order(:id)
        .limit(MAX_RULES)
        .pluck(:prefix, :domain)
        .filter_map do |prefix, domain|
          normalized_prefix = prefix.to_s.strip.downcase
          next if normalized_prefix.blank?

          {
            prefix: normalized_prefix,
            domain: domain.to_s.strip.downcase,
          }
        end

      RedisConnection.with do |redis|
        if rules.empty?
          redis.del(key(account_id))
        else
          redis.set(key(account_id), JSON.generate(rules))
        end

        redis.publish("timeline:system:#{account_id}", JSON.generate(event: 'custom_emoji_mutes_changed'))
      end
      rules
    rescue Redis::BaseError => e
      Rails.logger.warn("Unable to update custom emoji mute cache for account #{account_id}: #{e.class}")
      []
    end

    def delete(account_id)
      RedisConnection.with { |redis| redis.del(key(account_id)) }
    rescue Redis::BaseError => e
      Rails.logger.warn("Unable to delete custom emoji mute cache for account #{account_id}: #{e.class}")
    end

    def key(account_id)
      "#{KEY_PREFIX}:#{account_id}"
    end
  end
end
