# frozen_string_literal: true

class MisskeyCompat::DriveFileSerializer
  include RoutingHelper

  def self.serialize(media)
    new.serialize(media)
  end

  def serialize(media)
    {
      id: media.id.to_s,
      createdAt: media.created_at&.iso8601,
      name: media.file_file_name.presence || media.id.to_s,
      type: media.file_content_type.presence || 'application/octet-stream',
      md5: '',
      size: media.file_file_size || 0,
      isSensitive: false,
      blurhash: media.blurhash,
      properties: dimensions(media),
      url: full_asset_url(media.file.url(:original)),
      thumbnailUrl: full_asset_url(media.thumbnail.present? ? media.thumbnail.url(:original) : media.file.url(:small)),
      comment: media.description,
      folderId: nil,
      userId: media.account_id&.to_s,
    }
  end

  private

  def dimensions(media)
    original = media.file_meta&.dig('original')
    return {} if original.blank?

    { width: original['width'], height: original['height'] }.compact
  end
end
