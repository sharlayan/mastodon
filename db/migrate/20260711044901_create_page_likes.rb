# frozen_string_literal: true

class CreatePageLikes < ActiveRecord::Migration[8.1]
  def change
    create_table :page_likes do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :page,    null: false, foreign_key: { on_delete: :cascade }

      t.timestamps null: false
    end

    add_index :page_likes, [:account_id, :page_id], unique: true
  end
end
