# frozen_string_literal: true

RSS::Builder.build do |doc|
  doc.title("##{@tag.display_name}")
  doc.description(I18n.t('rss.descriptions.tag', hashtag: @tag.display_name))
  doc.link(tag_url(@tag))
  doc.last_build_date(@statuses.first.created_at) if @statuses.any?
  doc.generator("Mastodon v#{Mastodon::Version}")

  @statuses.each do |status|
    doc.item do |item|
      item.link(ActivityPub::TagManager.instance.url_for(status))
      item.pub_date(status.created_at)
      item.description(rss_status_content_format(status))

      if status.ordered_media_attachments.first&.audio?
        media = status.ordered_media_attachments.first
        item.enclosure(full_media_attachment_url(media, :original, include_filename: false), media.file_content_type, media.file_file_size)
      end

      status.ordered_media_attachments.each do |media_attachment|
        item.media_content(full_media_attachment_url(media_attachment, :original, include_filename: false), media_attachment.file_content_type, media_attachment.file_file_size) do |media_content|
          media_content.medium(media_attachment.gifv? ? 'image' : media_attachment.type.to_s)
          media_content.rating(status.sensitive? ? 'adult' : 'nonadult')
          media_content.description(media_attachment.description) if media_attachment.description.present?
          media_content.thumbnail(full_media_attachment_preview_url(media_attachment)) if full_media_attachment_preview_url(media_attachment)
        end
      end

      status.tags.each do |tag|
        item.category(tag.display_name)
      end
    end
  end
end
