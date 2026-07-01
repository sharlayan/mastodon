# frozen_string_literal: true

class AddAccountToBoardAnnouncements < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    safety_assured { add_reference :board_announcements, :account, null: true, foreign_key: { on_delete: :nullify }, index: false }
    add_index :board_announcements, :account_id, algorithm: :concurrently, where: 'account_id IS NOT NULL'
  end
end
