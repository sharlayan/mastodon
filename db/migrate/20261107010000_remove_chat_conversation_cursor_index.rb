# frozen_string_literal: true

class RemoveChatConversationCursorIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    remove_index :chat_conversations, name: :index_chat_conversations_on_cursor, algorithm: :concurrently
  end

  def down
    add_index :chat_conversations, [:last_message_id, :id], name: :index_chat_conversations_on_cursor, order: { last_message_id: 'DESC NULLS LAST', id: :desc }, algorithm: :concurrently
  end
end
