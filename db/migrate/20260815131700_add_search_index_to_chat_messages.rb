# frozen_string_literal: true

class AddSearchIndexToChatMessages < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :chat_messages, :text, using: :gin, opclass: :gin_trgm_ops, where: 'deleted_at IS NULL', algorithm: :concurrently, name: :index_visible_chat_messages_on_text_trigram
  end
end
