# frozen_string_literal: true

module Sharlayan::UpdateStatusServiceExtensions
  extend ActiveSupport::Concern

  private

  def prepare_sharlayan_media_attachments(next_media_attachments, added_media_attachments)
    raise Mastodon::ValidationError, I18n.t('chat.errors.media_in_use') if ChatMessageMediaAttachment.exists?(media_attachment_id: added_media_attachments.map(&:id))

    @next_media_attachments = next_media_attachments
    DriveFile.lock_for_media_attachments(added_media_attachments)
  end

  def apply_sharlayan_immediate_attributes
    apply_sharlayan_mfm_attributes if @options.key?(:text) || @options.key?(:content_type)

    return unless @options.key?(:sensitive) || @options.key?(:spoiler_text) || @options.key?(:media_ids)

    requested_sensitive = @options.key?(:sensitive) ? @options[:sensitive] : @status.sensitive?
    @status.sensitive = requested_sensitive || @options[:spoiler_text].present? || sensitive_drive_media?
  end

  def apply_sharlayan_mfm_attributes
    composition_allowed = Setting.mfm_enabled && Setting.mfm_allow_composition
    @status.content_type = 'text/plain' if @status.content_type == 'text/x-mfm' && !composition_allowed
    @status.mfm = composition_allowed && (@status.content_type == 'text/x-mfm' || MfmDetector.contains_mfm?(@status.text))
    @status.mfm_text = @status.mfm? ? @status.text : nil
  end

  def sensitive_drive_media?
    media_attachments = (@next_media_attachments || @status.ordered_media_attachments).to_a
    return false if media_attachments.empty?

    ActiveRecord::Associations::Preloader.new(records: media_attachments, associations: :drive_file).call
    media_attachments.any? { |media| media.drive_file&.sensitive? }
  end
end
