# frozen_string_literal: true

class AddChatConversationCursorIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :chat_conversations, [:last_message_id, :id], name: :index_chat_conversations_on_cursor, order: { last_message_id: 'DESC NULLS LAST', id: :desc }, algorithm: :concurrently
  end
end
