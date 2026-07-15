# frozen_string_literal: true

class CreateDriveFolders < ActiveRecord::Migration[8.1]
  def change
    create_table :drive_folders do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string     :name, null: false, default: ''
      t.bigint     :parent_id

      t.timestamps null: false
    end

    add_index :drive_folders, [:account_id, :parent_id, :id]

    safety_assured do
      add_foreign_key :drive_folders, :drive_folders, column: :parent_id, on_delete: :cascade
    end
  end
end
