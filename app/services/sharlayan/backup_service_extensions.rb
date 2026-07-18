# frozen_string_literal: true

module Sharlayan::BackupServiceExtensions
  private

  def dump_sharlayan_data!(zip)
    Sharlayan::PageBackupService.new(account).write_to_zip(zip) if Setting.pages_enabled
  end

  def dump_media_attachments!(zipfile)
    MediaAttachment.attached.where(account: account).includes(:drive_file).find_in_batches do |media_attachments|
      media_attachments.each do |media_attachment|
        attachment = media_attachment.drive_pointer? ? media_attachment.drive_file.file : media_attachment.file
        path = media_archive_path(media_attachment, attachment.url(:original))
        next if path.blank? || zipfile.find_entry(path)

        download_to_zip(zipfile, attachment, path)
      end

      GC.start
    end
  end

  def media_archive_path(media_attachment, source_url)
    if media_attachment&.drive_pointer?
      File.join('drive_files', media_attachment.drive_file_id.to_s, media_attachment.file_file_name)
    else
      Addressable::URI.parse(source_url).path.delete_prefix('/system/').delete_prefix('/')
    end
  end
end
