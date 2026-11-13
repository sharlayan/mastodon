# frozen_string_literal: true

class CreateMisskeyUserListFavorites < ActiveRecord::Migration[8.1]
  def change
    create_table :misskey_user_list_favorites do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :list, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps
    end

    add_index :misskey_user_list_favorites, [:account_id, :list_id], unique: true
  end
end
