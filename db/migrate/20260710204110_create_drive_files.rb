# frozen_string_literal: true

class CreateDriveFiles < ActiveRecord::Migration[8.1]
  def change
    create_table :drive_files do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.bigint     :folder_id

      t.string     :file_file_name
      t.string     :file_content_type
      t.integer    :file_file_size
      t.datetime   :file_updated_at
      t.json       :file_meta
      t.integer    :file_storage_schema_version

      t.string     :thumbnail_file_name
      t.string     :thumbnail_content_type
      t.integer    :thumbnail_file_size
      t.datetime   :thumbnail_updated_at
      t.integer    :thumbnail_storage_schema_version

      t.string     :blurhash
      t.integer    :type, null: false, default: 0
      t.text       :description
      t.boolean    :sensitive, null: false, default: false
      t.string     :sha256

      t.timestamps null: false
    end

    add_index :drive_files, [:account_id, :folder_id, :id]
    add_index :drive_files, [:account_id, :sha256]

    safety_assured do
      add_foreign_key :drive_files, :drive_folders, column: :folder_id, on_delete: :nullify
    end
  end
end
