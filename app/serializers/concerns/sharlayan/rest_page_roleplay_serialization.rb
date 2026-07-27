# frozen_string_literal: true

module Sharlayan::RESTPageRoleplaySerialization
  extend ActiveSupport::Concern

  include RoleplayModeHelper

  def roleplay_owner?
    return false unless roleplay_mode?

    role = scope&.role
    return false if role.nil? || role.everyone?

    cache = RequestStore.store[:page_serializer_roleplay_owner] ||= {}
    cache.fetch(role.id) do
      cache[role.id] = role.position == UserRole.assignable.maximum(:position)
    end
  end
end
