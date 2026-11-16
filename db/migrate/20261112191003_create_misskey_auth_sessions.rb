# frozen_string_literal: true

class CreateMisskeyAuthSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :misskey_auth_sessions do |t|
      t.string :token, null: false, index: { unique: true }
      t.references :oauth_application, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: true, foreign_key: { on_delete: :cascade }
      t.timestamps
    end
  end
end
