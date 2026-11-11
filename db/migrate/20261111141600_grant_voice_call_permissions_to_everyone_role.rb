# frozen_string_literal: true

class GrantVoiceCallPermissionsToEveryoneRole < ActiveRecord::Migration[8.1]
  VOICE_CALL_FLAGS = (1 << 2) | (1 << 3)

  def up
    safety_assured { execute "UPDATE user_roles SET extra_permissions = extra_permissions | #{VOICE_CALL_FLAGS} WHERE id = -99" }
  end

  def down
    safety_assured { execute "UPDATE user_roles SET extra_permissions = extra_permissions & ~#{VOICE_CALL_FLAGS}::bigint WHERE id = -99" }
  end
end
