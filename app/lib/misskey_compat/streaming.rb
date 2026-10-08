# frozen_string_literal: true

module MisskeyCompat
  module Streaming
    module_function

    def broadcast_note(redis, timeline_key, status, current_account: nil, current_account_id: nil)
      return unless Setting.misskey_compat_enabled
      return if status.nil?
      return unless redis.exists?("subscribed:misskey:#{timeline_key}")

      current_account ||= Account.find_by(id: current_account_id) if current_account_id
      note = MisskeyCompat::NoteSerializer.serialize(status, current_account: current_account)
      redis.publish("misskey:#{timeline_key}", JSON.generate({ event: 'note', payload: note }))
    rescue => e
      Rails.logger.warn("[misskey_compat] streaming broadcast failed for #{timeline_key}: #{e.class} #{e.message}")
    end

    def broadcast_reaction(redis, status, reaction, account, type)
      return unless Setting.misskey_compat_enabled
      return if status.nil? || reaction.nil? || account.nil?

      note_id = MisskeyCompat::MiId.encode(status.id)
      return unless redis.exists?("subscribed:misskey:note:#{note_id}")

      payload = {
        id: note_id,
        type: type,
        body: {
          reaction: reaction_key(reaction),
          userId: MisskeyCompat::MiId.encode(account.id),
        },
      }
      redis.publish("misskey:note:#{note_id}", JSON.generate({ event: 'noteUpdated', payload: payload }))
    rescue => e
      Rails.logger.warn("[misskey_compat] reaction broadcast failed for #{status&.id}: #{e.class} #{e.message}")
    end

    def broadcast_drive_file(redis, account, drive_file, type)
      broadcast_drive(redis, account, type) do
        type == 'fileDeleted' ? MisskeyCompat::MiId.encode(drive_id(drive_file)) : MisskeyCompat::DriveFileSerializer.serialize(drive_file)
      end
    end

    def broadcast_drive_folder(redis, account, drive_folder, type)
      broadcast_drive(redis, account, type) do
        type == 'folderDeleted' ? MisskeyCompat::MiId.encode(drive_id(drive_folder)) : MisskeyCompat::DriveFolderSerializer.serialize(drive_folder)
      end
    end

    def broadcast_drive(redis, account, type, body = nil)
      return unless Setting.misskey_compat_enabled
      return if account.nil?

      channel = "misskey:drive:#{account.id}"
      return unless redis.exists?("subscribed:#{channel}")

      body = yield if block_given?
      return if body.nil?

      redis.publish(channel, JSON.generate({ event: 'drive', payload: { type: type, body: body } }))
    rescue => e
      Rails.logger.warn("[misskey_compat] drive broadcast failed for #{account&.id}: #{e.class} #{e.message}")
    end

    def drive_id(record)
      record.respond_to?(:id) ? record.id : record
    end

    def reaction_key(reaction)
      custom = reaction.custom_emoji
      return reaction.name if custom.nil?

      host = custom.domain.presence
      host ? ":#{reaction.name}@#{host}:" : ":#{reaction.name}@.:"
    end
  end
end
