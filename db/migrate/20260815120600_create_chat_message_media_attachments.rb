# frozen_string_literal: true

class CreateChatMessageMediaAttachments < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_message_media_attachments do |t|
      t.references :chat_message, null: false, foreign_key: { on_delete: :cascade }
      t.references :media_attachment, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.timestamps
    end
  end
end
