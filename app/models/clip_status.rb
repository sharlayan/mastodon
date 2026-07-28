# frozen_string_literal: true

# == Schema Information
#
# Table name: clip_statuses
#
#  id         :bigint(8)        not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  clip_id    :bigint(8)        not null
#  status_id  :bigint(8)        not null
#

class ClipStatus < ApplicationRecord
  include Paginable

  belongs_to :clip
  belongs_to :status

  validates :status_id, uniqueness: { scope: :clip_id }
  validate :validate_clip_statuses_limit, on: :create

  after_destroy :invalidate_cleanup_info

  private

  def validate_clip_statuses_limit
    return if clip.nil?

    errors.add(:base, I18n.t('clips.errors.statuses_limit', limit: Clip::STATUSES_LIMIT)) if clip.clip_statuses.count >= Clip::STATUSES_LIMIT
  end

  def invalidate_cleanup_info
    return unless status&.account_id == clip&.account_id && status&.account&.local?

    status.account.statuses_cleanup_policy&.invalidate_last_inspected(status, :unclip)
  end
end
