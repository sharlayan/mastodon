# frozen_string_literal: true

module Sharlayan
  module AdminTimeline
    ROLEPLAY_ENV_KEY = 'OC_ROLEPLAY_OPTION'
    ENV_KEY = 'OC_ADMIN_TIMELINE_OPTION'

    REDIS_CHANNEL = 'timeline:admin'
    OWNER_REDIS_CHANNEL = 'timeline:admin:owner'
    FOLLOWERS_REDIS_CHANNEL_PREFIX = 'timeline:admin:followers'
    REMOVAL_REDIS_CHANNELS = [REDIS_CHANNEL, OWNER_REDIS_CHANNEL].freeze

    module_function

    def enabled?
      roleplay_mode? && ENV[ENV_KEY] == 'true'
    end

    def roleplay_mode?
      ENV[ROLEPLAY_ENV_KEY] == 'true'
    end

    def top_role_position
      ::UserRole.assignable.maximum(:position)
    end

    def owner_role_ids
      ::UserRole.assignable.where(position: top_role_position).pluck(:id)
    end

    def owner_account_ids
      ::Account.joins(:user).where(users: { role_id: owner_role_ids }).pluck(:id)
    end

    def owner_role?(role)
      return false if role.nil? || role.everyone?

      role.position == top_role_position
    end

    def owner_conversation?(status)
      return false unless status.direct_visibility?

      account_ids = owner_account_ids
      return false if account_ids.empty?

      account_ids.include?(status.account_id) || status.mentions.exists?(account_id: account_ids)
    end

    def role_can_view?(role)
      role&.can_extra?(:view_admin_timeline, :view_followers_admin_timeline) || false
    end

    def full_viewer_role?(role)
      role&.can_extra?(:view_admin_timeline) || false
    end

    def follower_viewer?(viewer, author)
      ::Follow.exists?(account_id: author.id, target_account_id: viewer.id)
    end

    def follower_redis_channel(account_id)
      "#{FOLLOWERS_REDIS_CHANNEL_PREFIX}:#{account_id}"
    end

    def follower_redis_channels_for(status, include_owner_conversation: false)
      return [] if !include_owner_conversation && owner_conversation?(status)

      status.account.active_relationships.pluck(:target_account_id).map { |account_id| follower_redis_channel(account_id) }
    end

    def redis_channels_for(status)
      channels = owner_conversation?(status) ? [OWNER_REDIS_CHANNEL] : [REDIS_CHANNEL, OWNER_REDIS_CHANNEL]
      channels + follower_redis_channels_for(status)
    end

    def removal_redis_channels_for(status)
      REMOVAL_REDIS_CHANNELS + follower_redis_channels_for(status, include_owner_conversation: true)
    end
  end
end
