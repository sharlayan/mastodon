# frozen_string_literal: true

class CreateBoardAnnouncementAttachments < ActiveRecord::Migration[8.0]
  def change
    create_table :board_announcement_attachments do |t|
      t.references :board_announcement, null: false, foreign_key: { on_delete: :cascade }
      t.integer :type, null: false, default: 0
      t.string :file_file_name
      t.string :file_content_type
      t.integer :file_file_size
      t.datetime :file_updated_at
      t.string :blurhash
      t.json :file_meta

      t.timestamps
    end
  end
end
