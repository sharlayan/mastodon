# frozen_string_literal: true

class MisskeyCompat::DriveFileSerializer
  include RoutingHelper

  def self.serialize(media, sensitive: nil)
    new.serialize(media, sensitive: sensitive)
  end

  def serialize(media, sensitive: nil)
    {
      id: MisskeyCompat::MiId.encode(media.id),
      createdAt: media.created_at&.iso8601,
      name: media.file_file_name.presence || media.id.to_s,
      type: media.file_content_type.presence || 'application/octet-stream',
      md5: '',
      size: media.file_file_size || 0,
      isSensitive: sensitive.nil? ? (media.status&.sensitive? || false) : sensitive,
      blurhash: media.blurhash,
      properties: dimensions(media),
      url: full_media_attachment_url(media),
      thumbnailUrl: full_media_attachment_preview_url(media),
      comment: media.description,
      folderId: nil,
      userId: MisskeyCompat::MiId.encode(media.account_id),
    }
  end

  private

  def dimensions(media)
    original = media.file_meta&.dig('original')
    return {} if original.blank?

    { width: original['width'], height: original['height'] }.compact
  end
end
