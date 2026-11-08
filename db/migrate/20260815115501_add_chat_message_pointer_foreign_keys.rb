# frozen_string_literal: true

class AddChatMessagePointerForeignKeys < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :chat_conversations, :chat_messages, column: :last_message_id, on_delete: :nullify, validate: false
    add_foreign_key :chat_memberships, :chat_messages, column: :last_read_message_id, on_delete: :nullify, validate: false
  end
end
