# frozen_string_literal: true

class CreateMisskeySystemWebhooks < ActiveRecord::Migration[8.1]
  def change
    create_table :misskey_system_webhooks do |t|
      t.references :webhook, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.string :name, null: false
      t.timestamps
    end
  end
end
