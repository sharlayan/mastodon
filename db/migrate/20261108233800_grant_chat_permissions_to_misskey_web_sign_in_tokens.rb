# frozen_string_literal: true

class GrantChatPermissionsToMisskeyWebSignInTokens < ActiveRecord::Migration[8.1]
  def up
    safety_assured do
      execute <<~SQL.squish
        UPDATE misskey_access_grants
        SET permissions = permissions || ARRAY(
              SELECT permission
              FROM unnest(ARRAY['read:chat', 'write:chat']::character varying[]) AS permission
              WHERE NOT permission = ANY(misskey_access_grants.permissions)
            ),
            updated_at = CURRENT_TIMESTAMP
        WHERE native_user_token = TRUE
          AND NOT permissions @> ARRAY['read:chat', 'write:chat']::character varying[]
      SQL
    end
  end

  def down; end
end
