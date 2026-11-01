# frozen_string_literal: true

class REST::ChatMessageReactionSerializer < ActiveModel::Serializer
  attributes :message_id, :reaction, :created_at
  belongs_to :account, serializer: REST::AccountSerializer

  def message_id
    object.chat_message_id.to_s
  end
end
