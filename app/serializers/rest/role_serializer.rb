# frozen_string_literal: true

class REST::RoleSerializer < ActiveModel::Serializer
  attributes :id, :name, :permissions, :color, :highlighted

  attribute :collection_limit
  attribute :extra_permissions

  def id
    object.id.to_s
  end

  def permissions
    object.computed_permissions.to_s
  end

  def extra_permissions
    object.computed_extra_permissions.to_s
  end
end
