# frozen_string_literal: true

class CreateRpHiddenStatuses < ActiveRecord::Migration[8.1]
  def change
    create_table :rp_hidden_statuses do |t|
      t.references :status, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.references :hidden_by_account, null: true, foreign_key: { to_table: :accounts, on_delete: :nullify }
      t.boolean :media_moved, null: false, default: false

      t.timestamps null: false
    end
  end
end
