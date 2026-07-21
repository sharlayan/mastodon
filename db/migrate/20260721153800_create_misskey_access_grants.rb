# frozen_string_literal: true

class CreateMisskeyAccessGrants < ActiveRecord::Migration[8.0]
  def up
    create_table :misskey_access_grants do |t|
      t.references :access_token, null: false, foreign_key: { to_table: :oauth_access_tokens, on_delete: :cascade }, index: { unique: true }
      t.string :permissions, array: true, null: false, default: []
      t.timestamps
    end

    safety_assured do
      execute <<~SQL.squish
        UPDATE oauth_access_tokens
        SET revoked_at = COALESCE(revoked_at, CURRENT_TIMESTAMP)
        FROM oauth_applications
        WHERE oauth_access_tokens.application_id = oauth_applications.id
          AND (oauth_applications.name = 'Misskey (MiAuth)' OR oauth_applications.name LIKE 'Misskey (MiAuth):%')
      SQL
    end
  end

  def down
    drop_table :misskey_access_grants
  end
end
