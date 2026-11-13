# frozen_string_literal: true

class GrantFlashPermissionsToMisskeyWebSignInTokens < ActiveRecord::Migration[8.1]
  PERMISSIONS = %w(read:flash write:flash read:flash-likes write:flash-likes).freeze

  def up
    permissions = "ARRAY[#{PERMISSIONS.map { |permission| connection.quote(permission) }.join(', ')}]::character varying[]"

    safety_assured do
      execute <<~SQL.squish
        UPDATE misskey_access_grants
        SET permissions = permissions || ARRAY(
              SELECT permission
              FROM unnest(#{permissions}) AS permission
              WHERE NOT permission = ANY(misskey_access_grants.permissions)
            ),
            updated_at = CURRENT_TIMESTAMP
        WHERE native_user_token = TRUE
          AND NOT permissions @> #{permissions}
      SQL
    end
  end

  def down; end
end
