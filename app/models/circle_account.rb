# frozen_string_literal: true

# == Schema Information
#
# Table name: circle_accounts
#
#  id         :bigint(8)        not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint(8)        not null
#  circle_id  :bigint(8)        not null
#  follow_id  :bigint(8)
#

class CircleAccount < ApplicationRecord
  belongs_to :circle
  belongs_to :account
  belongs_to :follow, optional: true

  validates :account_id, uniqueness: { scope: :circle_id }
  validate :validate_relationship

  before_validation :set_follow, unless: :circle_owner_account_is_account?

  private

  def set_follow
    self.follow = Follow.find_by(account_id: account.id, target_account_id: circle.account_id)
  end

  def validate_relationship
    return if circle_owner_account_is_account?

    errors.add(:account_id, :must_be_follower) if follow_id.nil?
    errors.add(:follow, :invalid) if follow_id.present? && follow.account_id != account_id
  end

  def circle_owner_account_is_account?
    circle.account_id == account_id
  end
end
