# frozen_string_literal: true

class CreateStatusReadReceipts < ActiveRecord::Migration[8.0]
  def change
    create_table :status_read_receipts do |t|
      t.references :status, null: false, foreign_key: { on_delete: :cascade }
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.datetime :read_at, null: false

      t.timestamps
    end

    add_index :status_read_receipts, [:status_id, :account_id], unique: true
  end
end
