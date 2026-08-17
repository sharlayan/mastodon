# frozen_string_literal: true

class ValidateAccountSwitchDeviceSessionForeignKey < ActiveRecord::Migration[8.1]
  def change
    validate_foreign_key :account_switch_devices, :session_activations
  end
end
