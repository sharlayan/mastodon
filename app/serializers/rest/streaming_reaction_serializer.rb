# frozen_string_literal: true

class REST::StreamingReactionSerializer < ActiveModel::Serializer
  include Sharlayan::REST::Reaction::EmojiAttributes

  has_many :users, serializer: REST::StreamingReactionUserSerializer

  def users
    object.respond_to?(:users) ? object.users : []
  end
end
