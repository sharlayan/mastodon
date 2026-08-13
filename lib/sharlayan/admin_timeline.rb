# frozen_string_literal: true

module Sharlayan
  module AdminTimeline
    ROLEPLAY_ENV_KEY = 'OC_ROLEPLAY_OPTION'
    ENV_KEY = 'OC_ADMIN_TIMELINE_OPTION'

    REDIS_CHANNEL = 'timeline:admin'
    OWNER_REDIS_CHANNEL = 'timeline:admin:owner'
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

    def redis_channels_for(status)
      owner_conversation?(status) ? [OWNER_REDIS_CHANNEL] : [REDIS_CHANNEL, OWNER_REDIS_CHANNEL]
    end
  end
end
