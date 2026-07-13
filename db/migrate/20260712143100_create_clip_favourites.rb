# frozen_string_literal: true

class CreateClipFavourites < ActiveRecord::Migration[8.1]
  def change
    create_table :clip_favourites do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :clip,    null: false, foreign_key: { on_delete: :cascade }

      t.timestamps null: false
    end

    add_index :clip_favourites, %i(account_id clip_id), unique: true
  end
end
