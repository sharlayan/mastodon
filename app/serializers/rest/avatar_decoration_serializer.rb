# frozen_string_literal: true

class REST::AvatarDecorationSerializer < ActiveModel::Serializer
  attributes :id, :name, :description, :url, :static_url, :category

  def id
    object.id.to_s
  end

  def category
    object.category&.name
  end

  def url
    object.image_url
  end

  def static_url
    object.image_static_url
  end
end
