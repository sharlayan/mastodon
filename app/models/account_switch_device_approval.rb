# frozen_string_literal: true

class AccountSwitchDeviceApproval < ApplicationRecord
  EXPIRATION = 10.minutes

  belongs_to :account
  belongs_to :target_account, class_name: 'Account'
  belongs_to :account_switch_device
  belongs_to :approved_by_device, class_name: 'AccountSwitchDevice', optional: true

  validates :expires_at, presence: true
  validate :accounts_and_device_match

  scope :pending, -> { where(approved_at: nil, denied_at: nil).where(expires_at: Time.current..) }

  def self.request!(account:, target_account:, account_switch_device:, request_ip:)
    approval = create_or_find_by!(account:, target_account:, account_switch_device:) do |new_approval|
      new_approval.request_ip = request_ip
      new_approval.expires_at = EXPIRATION.from_now
    end
    approval.update!(request_ip:, expires_at: EXPIRATION.from_now, approved_at: nil, denied_at: nil, approved_by_device: nil) unless approval.pending?
    approval
  end

  def approve!(device)
    transaction do
      lock!
      raise ActiveRecord::RecordNotFound unless pending? && approver_valid?(device)

      update!(approved_at: Time.current, approved_by_device: device)
      account_switch_device.update!(trusted_at: Time.current, revoked_at: nil)
    end
  end

  def deny!(device)
    transaction do
      lock!
      raise ActiveRecord::RecordNotFound unless pending? && approver_valid?(device)

      update!(denied_at: Time.current)
    end
  end

  def pending?
    approved_at.nil? && denied_at.nil? && expires_at.future?
  end

  private

  def approver_valid?(device)
    device.account_id == target_account_id && device.trusted? && device.id != account_switch_device_id
  end

  def accounts_and_device_match
    errors.add(:account_switch_device, :invalid) if account_switch_device&.account_id != target_account_id
    errors.add(:target_account, :invalid) unless AccountSwitchAuthorization.exists?(account_id:, target_account_id:)
  end
end
