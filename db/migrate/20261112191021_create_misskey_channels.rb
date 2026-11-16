# frozen_string_literal: true

class CreateMisskeyChannels < ActiveRecord::Migration[8.1]
  def change
    create_table :misskey_channels do |t|
      t.references :account, null: true, foreign_key: { on_delete: :nullify }
      t.string :name, null: false
      t.text :description
      t.references :banner_drive_file, null: true, foreign_key: { to_table: :drive_files, on_delete: :nullify }
      t.bigint :pinned_status_ids, array: true, null: false, default: []
      t.string :color, null: false, default: '#86b300'
      t.boolean :archived, null: false, default: false
      t.boolean :sensitive, null: false, default: false
      t.boolean :allow_renote_to_external, null: false, default: true
      t.integer :notes_count, null: false, default: 0
      t.integer :users_count, null: false, default: 0
      t.datetime :last_noted_at
      t.timestamps
    end

    add_index :misskey_channels, :last_noted_at
  end
end
