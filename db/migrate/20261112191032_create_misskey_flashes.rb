# frozen_string_literal: true

class CreateMisskeyFlashes < ActiveRecord::Migration[8.1]
  def change
    create_table :misskey_flashes do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :title, null: false, default: ''
      t.text :summary, null: false, default: ''
      t.text :script, null: false, default: ''
      t.string :permissions, array: true, null: false, default: []
      t.string :visibility, null: false, default: 'public'
      t.integer :likes_count, null: false, default: 0
      t.timestamps
    end

    add_index :misskey_flashes, :likes_count
  end
end
