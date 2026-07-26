# frozen_string_literal: true

class REST::ReactionSerializer < ActiveModel::Serializer
  include RoutingHelper

  attributes :name, :count

  attribute :me, if: :current_user?
  attribute :url, if: :custom_emoji?
  attribute :static_url, if: :custom_emoji?
  attribute :domain, if: :custom_emoji?
  attribute :local_counterpart, if: :custom_emoji?
  attribute(:is_sensitive, if: :custom_emoji?) { object.custom_emoji.is_sensitive }
  attribute :account_ids, if: :account_ids?

  has_many :users, serializer: REST::AccountSerializer

  def count
    object.has_attribute?(:count) ? object[:count] : 0
  end

  def current_user?
    !current_user.nil?
  end

  def custom_emoji?
    object.custom_emoji.present?
  end

  def account_ids?
    object.respond_to?(:account_ids) && object.account_ids.present?
  end

  def url
    full_asset_url(object.custom_emoji.image.url)
  end

  def static_url
    full_asset_url(object.custom_emoji.image.url(:static))
  end

  def users
    object.respond_to?(:users) ? object.users : []
  end

  def name
    if extern?
      [object.name, '@', object.custom_emoji.domain].join
    else
      object.name
    end
  end

  def domain
    if extern?
      object.custom_emoji.domain
    else
      ''
    end
  end

  def local_counterpart
    object.custom_emoji.local_counterpart.present?
  end

  private

  def extern?
    custom_emoji? && object.custom_emoji.domain.present?
  end
end
