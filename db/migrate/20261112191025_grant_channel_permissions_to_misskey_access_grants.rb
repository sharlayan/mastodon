# frozen_string_literal: true

class GrantChannelPermissionsToMisskeyAccessGrants < ActiveRecord::Migration[8.1]
  def up
    %w(read:channels write:channels).each { |permission| grant(permission) }
  end

  def down; end

  private

  def grant(permission)
    safety_assured do
      execute <<~SQL.squish
        UPDATE misskey_access_grants
        SET permissions = array_append(permissions, #{connection.quote(permission)}::character varying),
            updated_at = CURRENT_TIMESTAMP
        WHERE native_user_token = TRUE
          AND NOT #{connection.quote(permission)} = ANY(permissions)
      SQL
    end
  end
end
