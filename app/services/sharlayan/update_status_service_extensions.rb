# frozen_string_literal: true

module Sharlayan::UpdateStatusServiceExtensions
  extend ActiveSupport::Concern

  private

  def prepare_sharlayan_media_attachments(next_media_attachments, added_media_attachments)
    @next_media_attachments = next_media_attachments
    DriveFile.lock_for_media_attachments(added_media_attachments)
  end

  def apply_sharlayan_immediate_attributes
    @status.mfm_text = @status.mfm? ? @status.text : nil if @options.key?(:text)

    return unless @options.key?(:sensitive) || @options.key?(:spoiler_text) || @options.key?(:media_ids)

    requested_sensitive = @options.key?(:sensitive) ? @options[:sensitive] : @status.sensitive?
    @status.sensitive = requested_sensitive || @options[:spoiler_text].present? || sensitive_drive_media?
  end

  def sensitive_drive_media?
    media_attachments = @next_media_attachments || @status.ordered_media_attachments.includes(:drive_file)
    media_attachments.any? { |media| media.drive_file&.sensitive? }
  end
end
