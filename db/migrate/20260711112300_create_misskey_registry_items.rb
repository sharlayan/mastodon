# frozen_string_literal: true

class CreateMisskeyRegistryItems < ActiveRecord::Migration[8.1]
  def change
    create_table :misskey_registry_items do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :scope, array: true, null: false, default: []
      t.string :domain
      t.string :key, null: false, default: ''
      t.jsonb :value

      t.timestamps
    end

    add_index :misskey_registry_items, [:account_id, :domain, :scope]
  end
end
