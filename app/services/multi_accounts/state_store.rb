# frozen_string_literal: true

module MultiAccounts
  class StateStore
    STATE_TTL = 15.minutes.to_i
    KEY_PREFIX = 'multi_account:state:'

    class << self
      def store!(state, nonce, user_id, switch_parent_stack: nil, session_id: nil, reauthenticate_account_id: nil)
        data = {
          nonce: nonce,
          user_id: user_id,
          switch_parent_stack: switch_parent_stack,
          session_id: session_id,
          reauthenticate_account_id: reauthenticate_account_id,
          created_at: Time.now.utc.iso8601,
        }

        RedisConnection.with do |redis|
          redis.setex("#{KEY_PREFIX}#{state}", STATE_TTL, data.to_json)
        end
      end

      def update!(state, additional_data)
        existing = fetch(state)
        return false if existing.nil?

        merged = existing.merge(additional_data)
        RedisConnection.with do |redis|
          redis.setex("#{KEY_PREFIX}#{state}", STATE_TTL, merged.to_json)
        end
        true
      end

      def fetch(state)
        raw = RedisConnection.with do |redis|
          redis.get("#{KEY_PREFIX}#{state}")
        end
        return nil if raw.blank?

        JSON.parse(raw, symbolize_names: true)
      end

      def consume!(state, nonce)
        raw = RedisConnection.with do |redis|
          redis.getdel("#{KEY_PREFIX}#{state}")
        end
        return false if raw.blank? || nonce.blank?

        JSON.parse(raw, symbolize_names: true)[:nonce] == nonce
      end
    end
  end
end
