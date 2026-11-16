# frozen_string_literal: true

# == Schema Information
#
# Table name: misskey_gallery_posts
#
#  id                   :bigint(8)        not null, primary key
#  description          :text
#  likes_count          :integer          default(0), not null
#  media_attachment_ids :bigint(8)        default([]), not null, is an Array
#  sensitive            :boolean          default(FALSE), not null
#  title                :string           not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :bigint(8)        not null
#
class MisskeyGalleryPost < ApplicationRecord
  TITLE_LENGTH_LIMIT = 256
  DESCRIPTION_LENGTH_LIMIT = 2048
  FILES_LIMIT = 32
  RANKING_WINDOW = 3.days
  RANKING_THRESHOLD = 100

  belongs_to :account

  has_many :likes, class_name: 'MisskeyGalleryLike', inverse_of: :misskey_gallery_post, dependent: :delete_all

  validates :title, presence: true, length: { maximum: TITLE_LENGTH_LIMIT }
  validates :description, length: { maximum: DESCRIPTION_LENGTH_LIMIT }
  validate :validate_media_attachments

  scope :available_accounts, -> { joins(:account).merge(Account.without_suspended) }
  scope :popular, -> { available_accounts.where(likes_count: 1..).order(likes_count: :desc, id: :desc) }

  def self.ranking_ids(now: Time.current)
    window = RANKING_WINDOW.to_i
    previous_window_start = Time.zone.at(((now.to_i / window) - 1) * window)

    MisskeyGalleryLike
      .joins(:misskey_gallery_post)
      .where(misskey_gallery_likes: { created_at: previous_window_start.. })
      .where("misskey_gallery_likes.created_at - misskey_gallery_posts.created_at < ? * INTERVAL '1 second'", window)
      .group(:misskey_gallery_post_id)
      .order(Arel.sql('COUNT(*) DESC'), misskey_gallery_post_id: :desc)
      .limit(RANKING_THRESHOLD + 1)
      .pluck(:misskey_gallery_post_id)
  end

  def media_attachments
    return MediaAttachment.none if media_attachment_ids.empty?

    MediaAttachment.where(id: media_attachment_ids, account_id: account_id)
  end

  def ordered_media_attachments
    by_id = media_attachments.includes(drive_file: :custom_name).index_by(&:id)
    media_attachment_ids.filter_map { |id| by_id[id] }
  end

  def liked_by?(account)
    account.present? && likes.exists?(account_id: account.id)
  end

  private

  def validate_media_attachments
    ids = media_attachment_ids.uniq
    return errors.add(:media_attachment_ids, :blank) if ids.empty?
    return errors.add(:media_attachment_ids, :too_long, count: FILES_LIMIT) if ids.size > FILES_LIMIT
    return errors.add(:media_attachment_ids, :invalid) if ids.size != media_attachment_ids.size || account_id.blank?

    errors.add(:media_attachment_ids, :invalid) unless account.media_attachments.outside_chat.where(id: ids).count == ids.size
  end
end
