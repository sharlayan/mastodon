# frozen_string_literal: true

# == Schema Information
#
# Table name: misskey_ads
#
#  id           :bigint(8)        not null, primary key
#  day_of_week  :integer          default(0), not null
#  expires_at   :datetime         not null
#  image_url    :string           not null
#  is_sensitive :boolean          default(FALSE), not null
#  memo         :text             default(""), not null
#  place        :string           default(""), not null
#  priority     :string           default(""), not null
#  ratio        :integer          default(1), not null
#  starts_at    :datetime         not null
#  url          :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
class MisskeyAd < ApplicationRecord
  validates :url, :image_url, presence: true, length: { maximum: 1024 }
  validates :place, :priority, length: { maximum: 32 }
  validates :memo, length: { maximum: 8192 }
  validates :ratio, :day_of_week, numericality: { only_integer: true, greater_than_or_equal_to: -2_147_483_648, less_than_or_equal_to: 2_147_483_647 }
  validates :expires_at, :starts_at, presence: true

  scope :publishing, ->(now = Time.now.utc) { where(expires_at: now..).where(starts_at: ..now).where.not(expires_at: now) }
  scope :not_publishing, ->(now = Time.now.utc) { where(expires_at: ..now).or(where(starts_at: now..).where.not(starts_at: now)) }
  scope :for_day, ->(now = Time.now.utc) { where(day_of_week: 0).or(where('misskey_ads.day_of_week & ? > 0', 1 << now.wday)) }

  def to_log_human_identifier
    memo.presence&.truncate(64) || url
  end
end
