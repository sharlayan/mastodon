# frozen_string_literal: true

class MisskeyCompat::AnnouncementSerializer
  include RoutingHelper

  def self.serialize(announcement, current_account: nil)
    new.serialize(announcement, current_account: current_account)
  end

  def serialize(announcement, current_account: nil)
    data = {
      id: MisskeyCompat::MiId.encode(announcement.id),
      createdAt: (announcement.published_at || announcement.created_at).iso8601,
      updatedAt: announcement.updated_at&.iso8601,
      title: announcement.title,
      text: announcement.text,
      imageUrl: image_url_for(announcement),
      icon: announcement.icon,
      display: announcement.display,
      forYou: false,
      needConfirmationToRead: announcement.need_confirmation_to_read,
      silence: announcement.silence,
    }

    read = read_state(announcement, current_account)
    data[:isRead] = read unless read.nil?
    data
  end

  private

  def read_state(announcement, current_account)
    return nil if current_account.nil?
    return announcement.read_by_current_user if announcement.respond_to?(:read_by_current_user)

    announcement.read?(current_account)
  end

  def image_url_for(announcement)
    attachment = announcement.attachments.find(&:image?)
    return nil if attachment.nil?

    full_asset_url(attachment.file.url(:original))
  end
end
