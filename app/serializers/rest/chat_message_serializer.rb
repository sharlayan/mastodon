# frozen_string_literal: true

class REST::ChatMessageSerializer < ActiveModel::Serializer
  attributes :id, :conversation_id, :content, :created_at, :edited_at, :deleted_at, :reply_to_id, :remote, :deletes_for_everyone, :editable

  belongs_to :account, serializer: REST::AccountSerializer
  has_many :reactions, serializer: REST::ChatMessageReactionSerializer
  has_many :media_attachments, serializer: REST::MediaAttachmentSerializer

  def id
    object.id.to_s
  end

  def conversation_id
    object.chat_conversation_id.to_s
  end

  def content
    object.deleted? ? nil : object.text
  end

  def reply_to_id
    object.reply_to_id&.to_s
  end

  def remote
    object.remote?
  end

  def editable
    !object.deleted? && object.within_delete_window?
  end

  def deletes_for_everyone
    object.deletes_for_everyone?
  end
end
