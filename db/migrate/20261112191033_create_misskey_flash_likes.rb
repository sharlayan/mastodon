# frozen_string_literal: true

class CreateMisskeyFlashLikes < ActiveRecord::Migration[8.1]
  def change
    create_table :misskey_flash_likes do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :misskey_flash, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps
    end

    add_index :misskey_flash_likes, [:account_id, :misskey_flash_id], unique: true, name: 'index_misskey_flash_likes_on_account_id_and_flash_id'
  end
end
