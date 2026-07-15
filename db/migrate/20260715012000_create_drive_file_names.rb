# frozen_string_literal: true

class CreateDriveFileNames < ActiveRecord::Migration[8.1]
  def change
    create_table :drive_file_names do |t|
      t.references :drive_file, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.string     :name, null: false, default: '', limit: 128

      t.timestamps null: false
    end
  end
end
