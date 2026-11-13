# frozen_string_literal: true

class CreateMisskeyBubbleGameRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :misskey_bubble_game_records do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :seed, null: false
      t.datetime :seeded_at, null: false
      t.integer :score, null: false
      t.jsonb :logs, null: false, default: []
      t.string :game_mode, null: false
      t.integer :game_version, null: false
      t.boolean :is_verified, null: false, default: false
      t.timestamps
    end

    add_index :misskey_bubble_game_records, [:game_mode, :seeded_at]
  end
end
