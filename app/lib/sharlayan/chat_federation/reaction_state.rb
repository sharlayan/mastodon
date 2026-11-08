# frozen_string_literal: true

module Sharlayan
  module ChatFederation
    class ReactionState
      include Redisable

      TTL = 6.hours
      MAX_ACTIVE_IDS = 100
      MAX_ACTOR_ACTIVE_IDS = 1000
      MAX_CANCELLED_IDS = 1000
      MAX_MESSAGE_REACTIONS = 100
      ANONYMOUS_ID = 'anonymous'

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
        @actor = actor
        @message = message
        @reaction = reaction
        @cancelled_key = "chat_reaction_cancelled:#{actor.id}"
        @active_key = "chat_reaction_active:#{actor.id}:#{message.id}:#{Digest::SHA256.hexdigest(reaction)}"
        @actor_active_key = "chat_reaction_active_ids:#{actor.id}"
      end

      def accepts?(activity_id)
        return false unless room_for_reaction?

        prune_expired
        digest = digest_of(activity_id)
        return false if redis.zscore(@cancelled_key, digest)

        (redis.zscore(@active_key, digest).present? || redis.zcard(@active_key) < MAX_ACTIVE_IDS) &&
          (redis.zscore(@actor_active_key, actor_member(digest)).present? || redis.zcard(@actor_active_key) < MAX_ACTOR_ACTIVE_IDS)
      end

      def add(activity_id)
        digest = digest_of(activity_id)
        redis.eval(
          ADMIT_SCRIPT,
          keys: [@cancelled_key, @active_key, @actor_active_key],
          argv: [Time.current.to_i, TTL.from_now.to_i, TTL.to_i, digest, actor_member(digest), MAX_ACTIVE_IDS, MAX_ACTOR_ACTIVE_IDS]
        ) == 1
      end

      def remove(activity_id)
        prune_expired
        if activity_id.nil?
          members = redis.zrange(@active_key, 0, -1).map { |digest| actor_member(digest) }
          redis.multi do |transaction|
            transaction.zrem(@actor_active_key, members) if members.any?
            transaction.del(@active_key)
          end
          return true
        end

        digest = digest_of(activity_id)
        anonymous = digest_of(nil)
        redis.multi do |transaction|
          transaction.zadd(@cancelled_key, TTL.from_now.to_i, digest)
          transaction.zremrangebyrank(@cancelled_key, 0, -(MAX_CANCELLED_IDS + 1))
          transaction.expire(@cancelled_key, TTL.to_i)
          transaction.zrem(@active_key, [digest, anonymous])
          transaction.zrem(@actor_active_key, [actor_member(digest), actor_member(anonymous)])
        end
        redis.zcard(@active_key).zero?
      end

      private

      def room_for_reaction?
        @message.reactions.exists?(account_id: @actor.id, reaction: @reaction) ||
          @message.reactions.count < MAX_MESSAGE_REACTIONS
      end

      def digest_of(activity_id)
        Digest::SHA256.hexdigest(activity_id || ANONYMOUS_ID)
      end

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
