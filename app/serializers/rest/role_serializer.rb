# frozen_string_literal: true

class REST::RoleSerializer < ActiveModel::Serializer
  attributes :id, :name, :permissions, :color, :highlighted

  attributes :collection_limit, :page_limit, :daily_page_limit

  attribute :extra_permissions, if: :roleplay_mode_enabled?

  def id
    object.id.to_s
  end

  def permissions
    object.computed_permissions.to_s
  end

  def roleplay_mode_enabled?
    RoleplayModeHelper.roleplay_mode?
  end

  def extra_permissions
    object.computed_extra_permissions.to_s
  end
end
