# frozen_string_literal: true

class CreateMisskeyUserListSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :misskey_user_list_settings do |t|
      t.references :list, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.boolean :is_public, null: false, default: false
      t.timestamps
    end
  end
end
