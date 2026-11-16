# frozen_string_literal: true

class CreateMisskeyNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :misskey_notifications do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :from_account, null: true, foreign_key: { to_table: :accounts, on_delete: :cascade }
      t.string :notification_type, null: false
      t.jsonb :data, null: false, default: {}
      t.timestamps
    end

    add_index :misskey_notifications, [:account_id, :id], order: { id: :desc }
  end
end
