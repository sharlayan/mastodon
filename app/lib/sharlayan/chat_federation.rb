# frozen_string_literal: true

module Sharlayan::ChatFederation
  def self.enabled?
    !RoleplayModeHelper.roleplay_mode? && Setting.chat_federation_enabled
  end
end
