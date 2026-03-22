# frozen_string_literal: true

# == Schema Information
#
# Table name: account_switch_authorizations
#
#  id                :bigint(8)        not null, primary key
#  account_id        :bigint(8)        not null
#  target_account_id :bigint(8)        not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#

class AccountSwitchAuthorization < ApplicationRecord
  belongs_to :account
  belongs_to :target_account, class_name: 'Account'

  validates :target_account_id, uniqueness: { scope: :account_id }
  validate :not_self_referential

  scope :for_account, ->(account) { where(account: account) }

  private

  def not_self_referential
    errors.add(:target_account_id, 'cannot be the same as account') if account_id == target_account_id
  end
end
