# frozen_string_literal: true

class REST::ReactionEmojiSerializer < ActiveModel::Serializer
  include RoutingHelper

  attributes :name

  attribute :url, if: :custom_emoji?
  attribute :static_url, if: :custom_emoji?
  attribute :domain, if: :custom_emoji?
  attribute(:is_sensitive, if: :custom_emoji?) { object.custom_emoji.is_sensitive }

  def custom_emoji?
    object.custom_emoji.present?
  end

  def url
    full_asset_url(object.custom_emoji.image.url)
  end

  def static_url
    full_asset_url(object.custom_emoji.image.url(:static))
  end

  def name
    if extern?
      [object.name, '@', object.custom_emoji.domain].join
    else
      object.name
    end
  end

  def domain
    extern? ? object.custom_emoji.domain : ''
  end

  private

  def extern?
    custom_emoji? && object.custom_emoji.domain.present?
  end
end
