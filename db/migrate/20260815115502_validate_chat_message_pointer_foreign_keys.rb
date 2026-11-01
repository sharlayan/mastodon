# frozen_string_literal: true

class ValidateChatMessagePointerForeignKeys < ActiveRecord::Migration[8.1]
  def change
    validate_foreign_key :chat_conversations, :chat_messages, column: :last_message_id
    validate_foreign_key :chat_memberships, :chat_messages, column: :last_read_message_id
  end
end
