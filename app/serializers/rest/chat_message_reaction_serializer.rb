# frozen_string_literal: true

class REST::ChatMessageReactionSerializer < ActiveModel::Serializer
  include RoutingHelper

  attributes :message_id, :reaction, :created_at
  attribute :url, if: :custom_emoji?
  attribute :static_url, if: :custom_emoji?
  attribute :domain, if: :custom_emoji?
  attribute(:is_sensitive, if: :custom_emoji?) { custom_emoji.is_sensitive }

  belongs_to :account, serializer: REST::AccountSerializer

  def message_id
    object.chat_message_id.to_s
  end

  def url
    full_asset_url(custom_emoji.image.url)
  end

  def static_url
    full_asset_url(custom_emoji.image.url(:static))
  end

  def domain
    custom_emoji.domain
  end

  def custom_emoji?
    custom_emoji.present?
  end

  private

  def custom_emoji
    return @custom_emoji if defined?(@custom_emoji)

    @custom_emoji = object.custom_emoji
  end
end
