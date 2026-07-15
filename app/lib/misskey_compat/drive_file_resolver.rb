# frozen_string_literal: true

class MisskeyCompat::DriveFileResolver
  class NoSuchFileError < StandardError; end
  class AmbiguousFileError < StandardError; end

  def call(account:, file_ids:, allow_drive_files:, status: nil)
    ids = Array(file_ids).map(&:to_s).uniq
    return [] if ids.empty?

    media_by_id = eligible_media(account, ids, status).index_by { |media| media.id.to_s }
    drive_by_id = allow_drive_files ? account.drive_files.where(id: ids).order(:id).lock.index_by { |file| file.id.to_s } : {}
    pointer_by_drive_id = existing_pointers(status, drive_by_id.keys)

    media = ids.map do |id|
      media = media_by_id[id]
      drive_file = drive_by_id[id]
      raise AmbiguousFileError if media && drive_file
      raise NoSuchFileError if media.nil? && drive_file.nil?

      media || pointer_by_drive_id[id] || drive_file.build_pointer(account).tap(&:save!)
    end

    media.map { |item| item.id.to_s }
  end

  private

  def eligible_media(account, ids, status)
    scope = account.media_attachments.where(id: ids, scheduled_status_id: nil, drive_file_id: nil)
    status ? scope.where(status_id: [nil, status.id]) : scope.where(status_id: nil)
  end

  def existing_pointers(status, drive_ids)
    return {} if status.nil? || drive_ids.empty?

    status.media_attachments.where(drive_file_id: drive_ids).index_by { |media| media.drive_file_id.to_s }
  end
end
