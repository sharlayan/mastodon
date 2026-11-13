# frozen_string_literal: true

class MoveVoiceCallPermissionBits < ActiveRecord::Migration[8.1]
  PREVIOUS_GRANT_VERSION = '20261111141600'
  PREVIOUS_JOIN = 1 << 2
  PREVIOUS_SHARE = 1 << 3
  JOIN = 1 << 8
  SHARE = 1 << 9

  def up
    return unless previous_grant_applied?

    remap(PREVIOUS_JOIN => JOIN, PREVIOUS_SHARE => SHARE)
  end

  def down
    return unless previous_grant_applied?

    remap(JOIN => PREVIOUS_JOIN, SHARE => PREVIOUS_SHARE)
  end

  private

  def previous_grant_applied?
    select_value("SELECT 1 FROM schema_migrations WHERE version = '#{PREVIOUS_GRANT_VERSION}'").present?
  end

  def remap(bits)
    sources = bits.keys.reduce(0, :|)
    moved = bits.map { |from, to| "CASE WHEN extra_permissions & #{from} = #{from} THEN #{to} ELSE 0 END" }.join(' | ')
    safety_assured { execute "UPDATE user_roles SET extra_permissions = (extra_permissions & ~#{sources}::bigint) | #{moved} WHERE extra_permissions & #{sources} <> 0" }
  end
end
