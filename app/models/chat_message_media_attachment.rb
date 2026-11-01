# frozen_string_literal: true

class ChatMessageMediaAttachment < ApplicationRecord
  belongs_to :chat_message
  belongs_to :media_attachment

  validates :media_attachment_id, uniqueness: true
end
