# frozen_string_literal: true

class ActivityPub::MediaAttachmentPreviewSerializer < ActivityPub::ImageSerializer
  def url
    return super unless object.is_a?(MediaAttachment)

    full_media_attachment_preview_url(object)
  end

  def media_type
    return super unless object.is_a?(MediaAttachment)

    object.drive_file.preview_content_type
  end
end
