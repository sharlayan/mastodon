# frozen_string_literal: true

module Sharlayan
  module ChatFederation
    # Call while holding the message lock, after checking the reactor's access.
    class ReactionState
      include Redisable

      TTL = 6.hours
      MAX_ACTIVE_IDS = 100
      MAX_ACTOR_ACTIVE_IDS = 1000
      MAX_CANCELLED_IDS = 1000

      # Message locks do not serialize reactions to different messages by one actor.
      ADMIT_SCRIPT = <<~LUA
        for _, key in ipairs(KEYS) do
          redis.call('ZREMRANGEBYSCORE', key, '-inf', ARGV[1])
        end
        if redis.call('ZSCORE', KEYS[1], ARGV[4]) then
          return 0
        end
        if not redis.call('ZSCORE', KEYS[2], ARGV[4]) and redis.call('ZCARD', KEYS[2]) >= tonumber(ARGV[6]) then
          return 0
        end
        if not redis.call('ZSCORE', KEYS[3], ARGV[5]) and redis.call('ZCARD', KEYS[3]) >= tonumber(ARGV[7]) then
          return 0
        end
        redis.call('ZADD', KEYS[2], ARGV[2], ARGV[4])
        redis.call('EXPIRE', KEYS[2], ARGV[3])
        redis.call('ZADD', KEYS[3], ARGV[2], ARGV[5])
        redis.call('EXPIRE', KEYS[3], ARGV[3])
        return 1
      LUA

      def initialize(actor, message, reaction)
        @cancelled_key = "chat_reaction_cancelled:#{actor.id}"
        @active_key = "chat_reaction_active:#{actor.id}:#{message.id}:#{Digest::SHA256.hexdigest(reaction)}"
        @actor_active_key = "chat_reaction_active_ids:#{actor.id}"
      end

      def accepts?(activity_id)
        return true if activity_id.nil?

        prune_expired
        digest = Digest::SHA256.hexdigest(activity_id)
        return false if redis.zscore(@cancelled_key, digest)

        (redis.zscore(@active_key, digest).present? || redis.zcard(@active_key) < MAX_ACTIVE_IDS) &&
          (redis.zscore(@actor_active_key, actor_member(digest)).present? || redis.zcard(@actor_active_key) < MAX_ACTOR_ACTIVE_IDS)
      end

      def add(activity_id)
        return true if activity_id.nil?

        digest = Digest::SHA256.hexdigest(activity_id)
        redis.eval(
          ADMIT_SCRIPT,
          keys: [@cancelled_key, @active_key, @actor_active_key],
          argv: [Time.current.to_i, TTL.from_now.to_i, TTL.to_i, digest, actor_member(digest), MAX_ACTIVE_IDS, MAX_ACTOR_ACTIVE_IDS]
        ) == 1
      end

      def remove(activity_id)
        prune_expired
        # Older senders omitted IDs; preserve their existing undo behavior.
        if activity_id.nil?
          members = redis.zrange(@active_key, 0, -1).map { |digest| actor_member(digest) }
          redis.multi do |transaction|
            transaction.zrem(@actor_active_key, *members) if members.any?
            transaction.del(@active_key)
          end
          return true
        end

        digest = Digest::SHA256.hexdigest(activity_id)
        redis.multi do |transaction|
          transaction.zadd(@cancelled_key, TTL.from_now.to_i, digest)
          transaction.zremrangebyrank(@cancelled_key, 0, -(MAX_CANCELLED_IDS + 1))
          transaction.expire(@cancelled_key, TTL.to_i)
          transaction.zrem(@active_key, digest)
          transaction.zrem(@actor_active_key, actor_member(digest))
        end
        redis.zcard(@active_key).zero?
      end

      private

      def actor_member(digest)
        "#{@active_key}:#{digest}"
      end

      def prune_expired
        redis.multi do |transaction|
          transaction.zremrangebyscore(@cancelled_key, '-inf', Time.current.to_i)
          transaction.zremrangebyscore(@active_key, '-inf', Time.current.to_i)
          transaction.zremrangebyscore(@actor_active_key, '-inf', Time.current.to_i)
        end
      end
    end
  end
end
