# frozen_string_literal: true

module Sharlayan
  module SoftHide
    module_function

    # Deleting a status hides it instead of destroying it only while community
    # mode runs and the admin setting is on.
    def enabled?
      RoleplayModeHelper.roleplay_mode? && Setting.soft_hide_deletion
    end

    def hidden?(status)
      RoleplayModeHelper.roleplay_mode? && status.rp_hidden?
    end
  end
end
