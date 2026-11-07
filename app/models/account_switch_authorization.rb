# frozen_string_literal: true

# == Schema Information
#
# Table name: account_switch_authorizations
#
#  id                :bigint(8)        not null, primary key
#  push_forward      :boolean          default(FALSE), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint(8)        not null
#  target_account_id :bigint(8)        not null
#

class AccountSwitchAuthorization < ApplicationRecord
  belongs_to :account
  belongs_to :target_account, class_name: 'Account'

  validates :target_account_id, uniqueness: { scope: :account_id }
  validate :target_differs_from_account, on: :create

  scope :for_account, ->(account) { where(account: account) }
  scope :push_forwarding, -> { where(push_forward: true) }
  scope :linked, -> { where('account_switch_authorizations.account_id <> account_switch_authorizations.target_account_id') }

  private

  def target_differs_from_account
    errors.add(:target_account, :invalid) if account_id == target_account_id
  end
end
