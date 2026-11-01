# frozen_string_literal: true

class AddArchivedChatConversationsIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :chat_conversations, :archived_at, algorithm: :concurrently
  end
end
