# frozen_string_literal: true

class CreateCustomCsses < ActiveRecord::Migration[8.0]
  def change
    create_table :custom_csses do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.text :css, null: false, default: ''

      t.timestamps
    end
  end
end
