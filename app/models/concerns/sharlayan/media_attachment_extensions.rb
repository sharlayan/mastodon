# frozen_string_literal: true

module Sharlayan::MediaAttachmentExtensions
  extend ActiveSupport::Concern

  PAGE_REFERENCE_SQL = <<~SQL.squish.freeze
    EXISTS (
      SELECT 1
      FROM pages
      WHERE pages.account_id = media_attachments.account_id
        AND (pages.eye_catching_media_attachment_id = media_attachments.id
         OR jsonb_path_exists(
              pages.content,
              '$.** ? (@.fileId == $media_id)',
              jsonb_build_object('media_id', to_jsonb(media_attachments.id::text))
            ))
    )
  SQL

  included do
    belongs_to :drive_file, inverse_of: :media_attachments, optional: true

    validates :drive_access_key, uniqueness: true, format: { with: /\A[-_A-Za-z0-9]{43}\z/ }, if: :drive_pointer?

    scope :referenced_by_page, -> { where(PAGE_REFERENCE_SQL) }
    scope :in_use, -> { attached.or(referenced_by_page) }
    scope :unattached, -> { where(status_id: nil, scheduled_status_id: nil, status_draft_id: nil).where.not(PAGE_REFERENCE_SQL) }

    before_validation :generate_drive_access_key, if: :drive_pointer?
    before_save :lock_drive_file
  end

  def drive_pointer?
    drive_file_id.present?
  end

  private

  def lock_drive_file
    DriveFile.lock.find(drive_file_id) if drive_file_id.present?
  end

  def generate_drive_access_key
    self.drive_access_key ||= SecureRandom.urlsafe_base64(32)
  end
end
