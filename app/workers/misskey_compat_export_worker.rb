# frozen_string_literal: true

class MisskeyCompatExportWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'pull', retry: 3, dead: false

  def perform(user_id, entity)
    user = User.find_by(id: user_id)
    return if user.nil? || !user.functional? || !MisskeyCompat::DataExporter::ENTITIES.key?(entity)

    drive_file = MisskeyCompat::DataExporter.new(user).call(entity)
    MisskeyCompat::Notifier.notify!(user.account, 'exportCompleted', exportedEntity: entity, fileId: MisskeyCompat::MiId.encode(drive_file.id))
  rescue CreateDriveFileService::NoFreeSpaceError, ActiveRecord::RecordInvalid => e
    Rails.logger.warn("[misskey_compat] export #{entity} for user #{user_id} could not be stored: #{e.class}")
  end
end
