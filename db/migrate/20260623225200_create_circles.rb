# frozen_string_literal: true

class CreateCircles < ActiveRecord::Migration[8.1]
  def change
    create_table :circles do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string     :title,   null: false, default: ''

      t.timestamps null: false
    end

    create_table :circle_accounts do |t|
      t.references :circle, null: false, foreign_key: { on_delete: :cascade }
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :follow, null: true, foreign_key: { on_delete: :cascade }

      t.timestamps null: false
    end

    add_index :circle_accounts, %i(circle_id account_id), unique: true
  end
end
