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

  after_destroy :invalidate_cleanup_info

  private

  def invalidate_cleanup_info
    return unless status&.account_id == clip&.account_id && status&.account&.local?

    status.account.statuses_cleanup_policy&.invalidate_last_inspected(status, :unclip)
  end
end
