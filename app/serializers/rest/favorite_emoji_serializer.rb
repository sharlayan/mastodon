# frozen_string_literal: true

class REST::FavoriteEmojiSerializer < ActiveModel::Serializer
  attributes :name, :emoji_type, :position
end
