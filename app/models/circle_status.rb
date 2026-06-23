# frozen_string_literal: true

# == Schema Information
#
# Table name: circle_statuses
#
#  id         :bigint(8)        not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  circle_id  :bigint(8)        not null
#  status_id  :bigint(8)        not null
#

class CircleStatus < ApplicationRecord
  belongs_to :circle
  belongs_to :status

  validates :status_id, uniqueness: { scope: :circle_id }
  validate :validate_ownership

  private

  def validate_ownership
    errors.add(:status, :invalid) if status.present? && circle.present? && status.account_id != circle.account_id
  end
end
