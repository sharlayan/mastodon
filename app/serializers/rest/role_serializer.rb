# frozen_string_literal: true

class REST::RoleSerializer < ActiveModel::Serializer
  attributes :id, :name, :permissions, :color, :highlighted

  attributes :collection_limit, :page_limit

  def id
    object.id.to_s
  end

  def permissions
    object.computed_permissions.to_s
  end
end
