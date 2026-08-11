# frozen_string_literal: true

module Sharlayan
  module AdminTimeline
    ROLEPLAY_ENV_KEY = 'OC_ROLEPLAY_OPTION'
    ENV_KEY = 'OC_ADMIN_TIMELINE_OPTION'

    REDIS_CHANNEL = 'timeline:admin'

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
  end
end
