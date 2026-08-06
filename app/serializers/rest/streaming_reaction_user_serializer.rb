# frozen_string_literal: true

class REST::StreamingReactionUserSerializer < ActiveModel::Serializer
  include RoutingHelper
  include Sharlayan::REST::Account::Decorations

  attributes :id, :username, :acct, :display_name, :avatar, :avatar_static, :is_cat

  has_many :emojis, serializer: REST::CustomEmojiSerializer

  def id
    object.id.to_s
  end

  def acct
    object.pretty_acct
  end

  def display_name
    object.unavailable? ? '' : object.display_name
  end

  def avatar
    full_asset_url(object.unavailable? ? object.avatar.default_url : object.avatar_original_url)
  end

  def avatar_static
    full_asset_url(object.unavailable? ? object.avatar.default_url : object.avatar_static_url)
  end

  def emojis
    object.unavailable? ? [] : object.emojis
  end
end
