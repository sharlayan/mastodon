# frozen_string_literal: true

class REST::ReactionSerializer < ActiveModel::Serializer
  include Sharlayan::REST::Reaction::EmojiAttributes

  attribute :me, if: :current_user?
  attribute :local_counterpart, if: :custom_emoji?

  has_many :users, serializer: REST::AccountSerializer

  def current_user?
    respond_to?(:current_user) && !current_user.nil?
  end

  def local_counterpart
    object.custom_emoji.local_counterpart.present?
  end

  def users
    object.respond_to?(:users) ? object.users : []
  end
end
