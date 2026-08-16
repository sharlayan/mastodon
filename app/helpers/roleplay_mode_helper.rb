# frozen_string_literal: true

module RoleplayModeHelper
  def roleplay_mode?
    ENV['OC_ROLEPLAY_OPTION'] == 'true'
  end

  def roleplay_non_local_only_statuses?
    roleplay_mode? && Rails.configuration.x.roleplay_non_local_only_statuses == true
  end

  def roleplay_local_timeline_disabled?
    roleplay_mode? && Setting.roleplay_disable_local_timeline
  end

  def roleplay_public_timelines_hidden_from_admins?
    roleplay_mode? && Setting.roleplay_hide_public_timelines_from_admins
  end

  def force_local_only_leftover?
    !roleplay_mode? && Setting.force_local_only == true
  end

  module_function :roleplay_mode?
  module_function :roleplay_non_local_only_statuses?
  module_function :roleplay_local_timeline_disabled?
  module_function :roleplay_public_timelines_hidden_from_admins?
  module_function :force_local_only_leftover?
end
