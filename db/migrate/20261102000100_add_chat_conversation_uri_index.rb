# frozen_string_literal: true

class AddChatConversationUriIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :chat_conversations, :uri, unique: true, where: 'uri IS NOT NULL', algorithm: :concurrently, if_not_exists: true
    add_index :chat_messages, [:chat_conversation_id, :id], algorithm: :concurrently, if_not_exists: true
  end
end
