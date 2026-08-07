# frozen_string_literal: true

class TransferDriveFileToMediaAttachmentsService < BaseService
  class NotAttachedError < StandardError; end
  class UnsupportedFileError < StandardError; end
  class PageAttachedError < StandardError; end

  def call(drive_file)
    raise UnsupportedFileError unless MediaAttachment.supported_mime_types.include?(drive_file.file_content_type)

    drive_file.with_lock do
      pointers = drive_file.media_attachments.order(:id).lock.to_a
      raise PageAttachedError if MediaAttachment.where(id: pointers).referenced_by_page.exists?

      attached_ids = MediaAttachment.attached.where(id: pointers).ids.to_set
      attachments = pointers.select { |pointer| attached_ids.include?(pointer.id) }
      raise NotAttachedError if attachments.empty?

      attachments.each do |attachment|
        transfer_attachment(drive_file.file, attachment.file)
        transfer_attachment(drive_file.thumbnail, attachment.thumbnail) if drive_file.thumbnail.present?
        attachment.drive_file = nil
        attachment.save!
      end

      drive_file.destroy!
      attachments.size
    end
  end

  private

  def transfer_attachment(source, target)
    target.post_processing = false
    target.assign(source)

    target.styles.each_key do |style|
      next if style == :original || !source.styles.key?(style)

      target.queued_for_write[style] = Paperclip.io_adapters.for(source.styles[style])
    end
  end
end
