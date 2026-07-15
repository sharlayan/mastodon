# frozen_string_literal: true

module MediaComponentHelper
  def render_video_component(status, **)
    video = status.ordered_media_attachments.first

    meta = video.file_meta || {}

    component_params = {
      sensitive: sensitive_viewer?(status, current_account),
      src: full_media_attachment_url(video),
      preview: full_media_attachment_preview_url(video),
      alt: video.description,
      lang: status.language,
      blurhash: video.blurhash,
      frameRate: meta.dig('original', 'frame_rate'),
      aspectRatio: "#{meta.dig('original', 'width')} / #{meta.dig('original', 'height')}",
      media: [
        serialize_media_attachment(video),
      ].as_json,
    }.merge(**)

    react_component :video, component_params do
      render partial: 'statuses/attachment_list', locals: { attachments: status.ordered_media_attachments }
    end
  end

  def render_audio_component(status, **)
    audio = status.ordered_media_attachments.first

    meta = audio.file_meta || {}

    component_params = {
      src: full_media_attachment_url(audio),
      poster: full_media_attachment_preview_url(audio) || full_asset_url(status.account.avatar_static_url),
      alt: audio.description,
      lang: status.language,
      blurhash: audio.blurhash,
      backgroundColor: meta.dig('colors', 'background'),
      foregroundColor: meta.dig('colors', 'foreground'),
      accentColor: meta.dig('colors', 'accent'),
      duration: meta.dig('original', 'duration'),
    }.merge(**)

    react_component :audio, component_params do
      render partial: 'statuses/attachment_list', locals: { attachments: status.ordered_media_attachments }
    end
  end

  def render_media_gallery_component(status, **)
    component_params = {
      sensitive: sensitive_viewer?(status, current_account),
      autoplay: prefers_autoplay?,
      media: status.ordered_media_attachments.map { |a| serialize_media_attachment(a).as_json },
    }.merge(**)

    react_component :media_gallery, component_params do
      render partial: 'statuses/attachment_list', locals: { attachments: status.ordered_media_attachments }
    end
  end

  private

  def serialize_media_attachment(attachment)
    ActiveModelSerializers::SerializableResource.new(
      attachment,
      serializer: REST::MediaAttachmentSerializer
    )
  end

  def sensitive_viewer?(status, account)
    if !account.nil? && account.id == status.account_id
      status.sensitive
    else
      status.account.sensitized? || status.sensitive
    end
  end
end
