# frozen_string_literal: true

class GrantChatPermissionsToMisskeyAccessGrants < ActiveRecord::Migration[8.1]
  def up
    grant('read:chat', 'read:%')
    grant('write:chat', 'write:%')
  end

  def down; end

  private

  def grant(permission, kind)
    safety_assured do
      execute <<~SQL.squish
        UPDATE misskey_access_grants
        SET permissions = array_append(permissions, #{connection.quote(permission)}::character varying),
            updated_at = CURRENT_TIMESTAMP
        WHERE NOT #{connection.quote(permission)} = ANY(permissions)
          AND EXISTS (SELECT 1 FROM unnest(permissions) AS existing WHERE existing LIKE #{connection.quote(kind)})
      SQL
    end
  end
end
