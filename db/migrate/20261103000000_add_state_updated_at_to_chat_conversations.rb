# frozen_string_literal: true

class AddStateUpdatedAtToChatConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :chat_conversations, :state_updated_at, :datetime
  end
end
