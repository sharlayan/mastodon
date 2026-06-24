# frozen_string_literal: true

class REST::CustomEmojiMuteSerializer < ActiveModel::Serializer
  attributes :id, :prefix, :domain, :reject_reactions, :hide_in_picker, :created_at

  def id
    object.id.to_s
  end
end
