# frozen_string_literal: true

class MisskeyCompat::AnnouncementSerializer
  include RoutingHelper

  def self.serialize(announcement, current_account: nil)
    new.serialize(announcement, current_account: current_account)
  end

  def serialize(announcement, current_account: nil)
    {
      id: MisskeyCompat::MiId.encode(announcement.id),
      createdAt: (announcement.published_at || announcement.created_at).iso8601,
      updatedAt: announcement.updated_at&.iso8601,
      title: announcement.title,
      text: announcement.text,
      imageUrl: image_url_for(announcement),
      icon: 'info',
      display: 'dialog',
      forYou: false,
      needConfirmationToRead: false,
      silence: false,
      isRead: current_account ? announcement.read?(current_account) : undefined_read,
    }.compact
  end

  private

  def undefined_read
    nil
  end

  def image_url_for(announcement)
    attachment = announcement.attachments.find(&:image?)
    return nil if attachment.nil?

    full_asset_url(attachment.file.url(:original))
  end
end
