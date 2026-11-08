# frozen_string_literal: true

module Sharlayan::UserAccountSwitchRevocation
  extend ActiveSupport::Concern

  included do
    after_update_commit :revoke_account_switch_access, if: :saved_change_to_encrypted_password?
  end

  private

  def revoke_account_switch_access
    return if account_id.nil?

    AccountSwitchDevice.where(account_id: account_id).trusted.update_all(trusted_at: nil, updated_at: Time.current)
    AccountSwitchAuthorization.where(target_account_id: account_id).where.not(account_id: account_id).delete_all
  end
end
