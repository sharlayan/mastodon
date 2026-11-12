# frozen_string_literal: true

class CreateMisskeyWebhooks < ActiveRecord::Migration[8.1]
  def change
    create_table :misskey_webhooks do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.string :url, null: false
      t.string :secret, null: false, default: ''
      t.string :events, array: true, null: false, default: []
      t.boolean :active, null: false, default: true
      t.datetime :latest_sent_at
      t.integer :latest_status
      t.timestamps
    end
  end
end
