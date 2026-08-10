# frozen_string_literal: true

module RoleplayModeHelper
  def roleplay_mode?
    ENV['OC_ROLEPLAY_OPTION'] == 'true'
  end

  def roleplay_non_local_only_statuses?
    roleplay_mode? && Rails.configuration.x.roleplay_non_local_only_statuses == true
  end

  def force_local_only_leftover?
    !roleplay_mode? && Setting.force_local_only == true
  end

  module_function :roleplay_mode?
  module_function :roleplay_non_local_only_statuses?
  module_function :force_local_only_leftover?
end
