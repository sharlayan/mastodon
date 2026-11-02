# frozen_string_literal: true

class AddChatFederationFields < ActiveRecord::Migration[8.1]
  def change
    add_column :chat_conversations, :uri, :string
    add_column :accounts, :chat_scope, :string
    add_column :accounts, :can_chat, :boolean, default: true, null: false
  end
end
