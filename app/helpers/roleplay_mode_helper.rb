# frozen_string_literal: true

module RoleplayModeHelper
  def roleplay_mode?
    ENV['OC_ROLEPLAY_OPTION'] == 'true'
  end

  module_function :roleplay_mode?
end
