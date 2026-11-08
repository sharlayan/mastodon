# frozen_string_literal: true

class AddUriToChatMessageReactions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :chat_message_reactions, :uri, :string
    add_index :chat_message_reactions, :uri, where: 'uri IS NOT NULL', algorithm: :concurrently
  end
end
