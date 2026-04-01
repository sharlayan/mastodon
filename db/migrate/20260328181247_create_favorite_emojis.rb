# frozen_string_literal: true

class CreateFavoriteEmojis < ActiveRecord::Migration[7.2]
  def change
    create_table :favorite_emojis do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.string :emoji_type, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :favorite_emojis, [:account_id, :name], unique: true
  end
end
