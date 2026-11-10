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

  PARENT_NOTIFICATION_SESSION_JOINS = <<~SQL.squish.freeze
    INNER JOIN users ON users.id = session_activations.user_id
    INNER JOIN account_switch_devices child_devices
      ON child_devices.session_activation_id = session_activations.id
      AND child_devices.account_id = users.account_id
      AND child_devices.trusted_at IS NOT NULL
      AND child_devices.revoked_at IS NULL
    INNER JOIN account_switch_authorizations
      ON account_switch_authorizations.target_account_id = child_devices.account_id
      AND account_switch_authorizations.account_id <> account_switch_authorizations.target_account_id
    INNER JOIN account_switch_devices root_devices
      ON root_devices.account_id = account_switch_authorizations.account_id
      AND root_devices.token_digest = child_devices.token_digest
      AND root_devices.trusted_at IS NOT NULL
      AND root_devices.revoked_at IS NULL
  SQL

  def self.parent_notification_sessions(root_account_id)
    SessionActivation
      .joins(PARENT_NOTIFICATION_SESSION_JOINS)
      .where(account_switch_authorizations: { account_id: root_account_id })
      .where.not(access_token_id: nil)
  end

  def trusted?
    trusted_at.present? && revoked_at.nil?
  end

  def revoke!
    transaction do
      lock!
      session_activation.destroy! if session_activation&.user&.account_id == account_id
      update!(revoked_at: Time.current, session_activation: nil)
    end
  end
end
