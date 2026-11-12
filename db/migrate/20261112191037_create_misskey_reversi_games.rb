# frozen_string_literal: true

class CreateMisskeyReversiGames < ActiveRecord::Migration[8.1]
  def change
    create_table :misskey_reversi_games do |t|
      t.references :account1, null: false, foreign_key: { to_table: :accounts, on_delete: :cascade }
      t.references :account2, null: false, foreign_key: { to_table: :accounts, on_delete: :cascade }
      t.boolean :account1_ready, null: false, default: false
      t.boolean :account2_ready, null: false, default: false
      t.integer :black
      t.datetime :started_at
      t.datetime :ended_at
      t.bigint :winner_account_id
      t.bigint :surrendered_account_id
      t.bigint :timeout_account_id
      t.integer :time_limit_for_each_turn, null: false, default: 90
      t.jsonb :logs, null: false, default: []
      t.string :map, array: true, null: false, default: []
      t.string :bw, null: false, default: 'random'
      t.boolean :no_irregular_rules, null: false, default: false
      t.boolean :llotheo, null: false, default: false
      t.boolean :can_put_everywhere, null: false, default: false
      t.boolean :looped_board, null: false, default: false
      t.string :crc32
      t.timestamps
    end
  end
end
