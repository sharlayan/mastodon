# frozen_string_literal: true

class CreateBoardAnnouncementReads < ActiveRecord::Migration[8.0]
  def change
    create_table :board_announcement_reads do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :board_announcement, null: false, foreign_key: { on_delete: :cascade }

      t.timestamps
    end

    add_index :board_announcement_reads, [:account_id, :board_announcement_id], unique: true, name: :index_board_announcement_reads_on_account_and_announcement
  end
end
