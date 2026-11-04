# frozen_string_literal: true

class CreateChatMessageEdits < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_message_edits do |t|
      t.references :chat_message, null: false, foreign_key: { on_delete: :cascade }
      t.text :text
      t.datetime :created_at, null: false
    end
  end
end
