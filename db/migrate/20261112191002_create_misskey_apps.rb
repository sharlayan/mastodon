# frozen_string_literal: true

class CreateMisskeyApps < ActiveRecord::Migration[8.1]
  def change
    create_table :misskey_apps do |t|
      t.references :oauth_application, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.text :description, null: false, default: ''
      t.string :permission, array: true, null: false, default: []
      t.string :callback_url
      t.timestamps
    end
  end
end
