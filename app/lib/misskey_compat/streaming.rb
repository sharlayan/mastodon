# frozen_string_literal: true

module MisskeyCompat
  module Streaming
    module_function

    def broadcast_note(redis, timeline_key, status, current_account: nil)
      return unless Setting.misskey_compat_enabled
      return if status.nil?
      return unless redis.exists?("subscribed:misskey:#{timeline_key}")

      note = MisskeyCompat::NoteSerializer.serialize(status, current_account: current_account)
      redis.publish("misskey:#{timeline_key}", JSON.generate({ event: 'note', payload: note }))
    rescue => e
      Rails.logger.warn("[misskey_compat] streaming broadcast failed for #{timeline_key}: #{e.class} #{e.message}")
    end
  end
end
