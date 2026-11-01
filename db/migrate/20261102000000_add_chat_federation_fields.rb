# frozen_string_literal: true

class AddChatFederationFields < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :chat_conversations, :uri, :string
    add_index :chat_conversations, :uri, unique: true, where: 'uri IS NOT NULL', algorithm: :concurrently

    add_column :chat_invitations, :uri, :string

    add_column :accounts, :chat_scope, :string
    add_column :accounts, :can_chat, :boolean
  end
end