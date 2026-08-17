# frozen_string_literal: true

class AccountSwitchDevice < ApplicationRecord
  belongs_to :account
  belongs_to :session_activation, optional: true

  has_many :approval_requests, class_name: 'AccountSwitchDeviceApproval', dependent: :destroy
  has_many :approved_requests, class_name: 'AccountSwitchDeviceApproval', foreign_key: :approved_by_device_id, inverse_of: :approved_by_device, dependent: :nullify

  validates :token_digest, uniqueness: { scope: :account_id }
  validates :first_seen_at, :last_seen_at, presence: true

  scope :trusted, -> { where.not(trusted_at: nil).where(revoked_at: nil) }

  def trusted?
    trusted_at.present? && revoked_at.nil?
  end

  def revoke!
    transaction do
      lock!
      session_activation&.destroy!
      update!(revoked_at: Time.current, session_activation: nil)
    end
  end
end
