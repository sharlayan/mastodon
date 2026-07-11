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

    def broadcast_reaction(redis, status, reaction, account, type)
      return unless Setting.misskey_compat_enabled
      return if status.nil? || reaction.nil? || account.nil?
      return unless redis.exists?("subscribed:misskey:note:#{status.id}")

      payload = {
        id: status.id.to_s,
        type: type,
        body: {
          reaction: reaction_key(reaction),
          userId: account.id.to_s,
        },
      }
      redis.publish("misskey:note:#{status.id}", JSON.generate({ event: 'noteUpdated', payload: payload }))
    rescue => e
      Rails.logger.warn("[misskey_compat] reaction broadcast failed for #{status&.id}: #{e.class} #{e.message}")
    end

    def reaction_key(reaction)
      custom = reaction.custom_emoji
      return reaction.name if custom.nil?

      host = custom.domain.presence
      host ? ":#{reaction.name}@#{host}:" : ":#{reaction.name}@.:"
    end
  end
end
