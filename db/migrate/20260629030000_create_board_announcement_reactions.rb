# frozen_string_literal: true

class CreateBoardAnnouncementReactions < ActiveRecord::Migration[8.0]
  def change
    create_table :board_announcement_reactions do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :board_announcement, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :name, null: false, default: ''
      t.references :custom_emoji, foreign_key: { on_delete: :cascade }, index: { where: 'custom_emoji_id IS NOT NULL' }

      t.timestamps
    end

    add_index :board_announcement_reactions, [:account_id, :board_announcement_id, :name], unique: true, name: :index_board_announcement_reactions_on_account_and_announcement
    add_index :board_announcement_reactions, :board_announcement_id
  end
end
