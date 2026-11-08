# frozen_string_literal: true

module Sharlayan::MediaAttachmentExtensions
  extend ActiveSupport::Concern

  CHAT_REFERENCE_SQL = <<~SQL.squish.freeze
    EXISTS (
      SELECT 1 FROM chat_message_media_attachments
      WHERE chat_message_media_attachments.media_attachment_id = media_attachments.id
    )
  SQL

  PAGE_REFERENCE_SQL = <<~SQL.squish.freeze
    EXISTS (
      SELECT 1
      FROM pages
      WHERE pages.account_id = media_attachments.account_id
        AND (pages.eye_catching_media_attachment_id = media_attachments.id
         OR pages.referenced_media_attachment_ids @> ARRAY[media_attachments.id])
    )
    OR EXISTS (
      SELECT 1
      FROM page_series
      WHERE page_series.account_id = media_attachments.account_id
        AND page_series.cover_media_attachment_id = media_attachments.id
    )
  SQL

  included do
    has_many :chat_message_media_attachments, dependent: :destroy
    has_many :chat_messages, through: :chat_message_media_attachments

    belongs_to :drive_file, inverse_of: :media_attachments, optional: true

    validates :drive_access_key, uniqueness: true, format: { with: /\A[-_A-Za-z0-9]{43}\z/ }, if: :drive_pointer?

    scope :attached, -> { where.not(status_id: nil).or(where.not(scheduled_status_id: nil)).or(where.not(status_draft_id: nil)).or(where(CHAT_REFERENCE_SQL)) }
    scope :referenced_by_page, -> { where(PAGE_REFERENCE_SQL) }
    scope :in_use, -> { attached.or(referenced_by_page) }
    scope :unattached, -> { where(status_id: nil, scheduled_status_id: nil, status_draft_id: nil).where.not(PAGE_REFERENCE_SQL).where.not(CHAT_REFERENCE_SQL) }

    before_validation :generate_drive_access_key, if: :drive_pointer?
    before_save :lock_drive_file
  end

  def drive_pointer?
    drive_file_id.present?
  end

  def chat_attachment?
    status_id.nil? && chat_message_media_attachments.any?
  end

  def removable_with_chat_message?
    status_id.nil? && scheduled_status_id.nil? && status_draft_id.nil? && !self.class.referenced_by_page.exists?(id: id)
  end

  private

  def lock_drive_file
    DriveFile.lock.find(drive_file_id) if drive_file_id.present?
  end

  def generate_drive_access_key
    self.drive_access_key ||= SecureRandom.urlsafe_base64(32)
  end
end
