# frozen_string_literal: true

# == Schema Information
#
# Table name: chat_message_media_attachments
#
#  id                  :bigint(8)        not null, primary key
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  chat_message_id     :bigint(8)        not null
#  media_attachment_id :bigint(8)        not null
#
class ChatMessageMediaAttachment < ApplicationRecord
  belongs_to :chat_message
  belongs_to :media_attachment

  validates :media_attachment_id, uniqueness: true
end
