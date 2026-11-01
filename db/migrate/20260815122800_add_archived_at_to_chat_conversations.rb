# frozen_string_literal: true

class AddArchivedAtToChatConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :chat_conversations, :archived_at, :datetime
  end
end
