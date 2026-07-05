# frozen_string_literal: true

class CreateAntennaDomains < ActiveRecord::Migration[8.1]
  def change
    create_table :antenna_domains do |t|
      t.references :antenna, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false, default: ''
      t.boolean :exclude, null: false, default: false

      t.timestamps
    end
  end
end
