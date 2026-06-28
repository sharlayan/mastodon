# frozen_string_literal: true

# == Schema Information
#
# Table name: board_announcements
#
#  id           :bigint(8)        not null, primary key
#  published    :boolean          default(FALSE), not null
#  published_at :datetime
#  text         :text             default(""), not null
#  text_html    :text             default(""), not null
#  title        :string           default(""), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#

class BoardAnnouncement < ApplicationRecord
  scope :published, -> { where(published: true) }
  scope :reverse_chronological, -> { order(coalesced_timestamp.desc) }

  has_many :reads, class_name: 'BoardAnnouncementRead', dependent: :destroy, inverse_of: :board_announcement
  has_many :attachments, class_name: 'BoardAnnouncementAttachment', dependent: :destroy, inverse_of: :board_announcement

  validates :title, presence: true, length: { maximum: 256 }
  validates :text, presence: true, length: { maximum: 65_535 }

  before_save :render_text_html
  before_save :set_published_at

  class << self
    def coalesced_timestamp
      Arel.sql('COALESCE(board_announcements.published_at, board_announcements.created_at)')
    end
  end

  def to_log_human_identifier
    title
  end

  def publish!
    update!(published: true, published_at: published_at || Time.now.utc)
  end

  def unpublish!
    update!(published: false)
  end

  def read?(account)
    return false if account.nil?

    reads.exists?(account_id: account.id)
  end

  private

  def render_text_html
    return unless title_changed? || text_changed?

    self.text_html = BoardAnnouncementFormatter.new(text).to_html
  end

  def set_published_at
    self.published_at = Time.now.utc if published? && published_at.blank?
  end
end
