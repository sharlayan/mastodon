# frozen_string_literal: true

# == Schema Information
#
# Table name: account_switch_devices
#
#  id                    :bigint(8)        not null, primary key
#  first_seen_at         :datetime         not null
#  first_seen_ip         :inet
#  last_seen_at          :datetime         not null
#  last_seen_ip          :inet
#  revoked_at            :datetime
#  token_digest          :string           not null
#  trusted_at            :datetime
#  user_agent            :string
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :bigint(8)        not null
#  session_activation_id :bigint(8)
#
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
