# frozen_string_literal: true

class CreateClips < ActiveRecord::Migration[8.1]
  def change
    create_table :clips do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string     :title,       null: false, default: ''
      t.text       :description, null: true
      t.boolean    :public,      null: false, default: false

      t.timestamps null: false
    end
  end
end
