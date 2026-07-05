# frozen_string_literal: true

class CreateAntennaAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :antenna_accounts do |t|
      t.references :antenna, null: false, foreign_key: { on_delete: :cascade }
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.boolean :exclude, null: false, default: false

      t.timestamps
    end

    add_index :antenna_accounts, [:antenna_id, :account_id], unique: true
  end
end
