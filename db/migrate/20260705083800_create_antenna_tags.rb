# frozen_string_literal: true

class CreateAntennaTags < ActiveRecord::Migration[8.1]
  def change
    create_table :antenna_tags do |t|
      t.references :antenna, null: false, foreign_key: { on_delete: :cascade }
      t.references :tag, null: false, foreign_key: { on_delete: :cascade }
      t.boolean :exclude, null: false, default: false

      t.timestamps
    end

    add_index :antenna_tags, [:antenna_id, :tag_id], unique: true
  end
end
