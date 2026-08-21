# frozen_string_literal: true

module Sharlayan
  module SoftHide
    module_function

    def enabled?
      RoleplayModeHelper.roleplay_mode? && Setting.soft_hide_deletion
    end

    def hidden?(status)
      RoleplayModeHelper.roleplay_mode? && status.rp_hidden?
    end
  end
end
