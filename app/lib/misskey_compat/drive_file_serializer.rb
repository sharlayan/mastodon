# frozen_string_literal: true

class MisskeyCompat::DriveFileSerializer
  include RoutingHelper

  def self.serialize(media, sensitive: nil)
    new.serialize(media, sensitive: sensitive)
  end

  def serialize(media, sensitive: nil)
    if media.is_a?(MediaAttachment) && media.drive_pointer?
      sensitive = media.drive_file.sensitive? if sensitive.nil?
      return serialize_drive_file(media.drive_file, sensitive: sensitive)
    end

    return serialize_drive_file(media, sensitive: sensitive) if media.is_a?(DriveFile)

    {
      id: MisskeyCompat::MiId.encode(media.id),
      createdAt: media.created_at&.iso8601,
      name: media.file_file_name.presence || media.id.to_s,
      type: media.file_content_type.presence || 'application/octet-stream',
      md5: media_md5(media),
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

  def media_md5(media)
    stored = media.file_meta.is_a?(Hash) ? media.file_meta['md5'].presence : nil
    return stored if stored

    MisskeyCompat::MediaAttachmentMd5.for(media).to_s
  end

  def serialize_drive_file(file, sensitive: nil)
    {
      id: MisskeyCompat::MiId.encode(file.id),
      createdAt: file.created_at&.iso8601,
      name: file.display_name,
      type: file.file_content_type.presence || 'application/octet-stream',
      md5: file.md5.presence || '',
      size: file.file_file_size || 0,
      isSensitive: sensitive.nil? ? file.sensitive? : sensitive,
      blurhash: file.blurhash,
      properties: dimensions(file),
      url: full_asset_url(file.file.url(:original)),
      thumbnailUrl: drive_file_thumbnail_url(file),
      comment: file.description,
      folderId: MisskeyCompat::MiId.encode(file.folder_id),
      userId: MisskeyCompat::MiId.encode(file.account_id),
    }
  end

  def drive_file_thumbnail_url(file)
    source = if file.thumbnail.present?
               file.thumbnail.url(:original)
             elsif file.file.styles.key?(:small)
               file.file.url(:small)
             else
               file.file.url(:original)
             end

    full_asset_url(source)
  end

  def dimensions(media)
    original = media.file_meta&.dig('original')
    return {} if original.blank?

    { width: original['width'], height: original['height'] }.compact
  end
end
