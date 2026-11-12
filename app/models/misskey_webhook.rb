# frozen_string_literal: true

# == Schema Information
#
# Table name: misskey_webhooks
#
#  id             :bigint(8)        not null, primary key
#  active         :boolean          default(TRUE), not null
#  events         :string           default([]), not null, is an Array
#  latest_sent_at :datetime
#  latest_status  :integer
#  name           :string           not null
#  secret         :string           default(""), not null
#  url            :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint(8)        not null
#
class MisskeyWebhook < ApplicationRecord
  EVENTS = %w(mention unfollow follow followed note reply renote reaction).freeze
  LIMIT = 3
  ANY_ACTIVE_CACHE_KEY = 'misskey_webhooks:any_active'

  belongs_to :account

  after_commit :expire_any_active_cache

  scope :active, -> { where(active: true) }
  scope :listening_to, ->(event) { where('? = ANY(events)', event) }

  validates :name, presence: true, length: { maximum: 100 }
  validates :url, presence: true, length: { maximum: 1024 }, url: true
  validates :secret, length: { maximum: 1024 }
  validate :validate_events

  def self.any_active?
    Rails.cache.fetch(ANY_ACTIVE_CACHE_KEY, expires_in: 10.minutes) { active.exists? }
  end

  def record_delivery!(status)
    update_columns(latest_sent_at: Time.now.utc, latest_status: status)
  end

  private

  def expire_any_active_cache
    Rails.cache.delete(ANY_ACTIVE_CACHE_KEY)
  end

  def validate_events
    errors.add(:events, :invalid) unless events.is_a?(Array) && events.difference(EVENTS).empty?
  end
end
