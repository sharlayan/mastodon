# frozen_string_literal: true

class BindAccountSwitchDevicesToSessions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_reference :account_switch_devices, :session_activation, index: { algorithm: :concurrently } unless column_exists?(:account_switch_devices, :session_activation_id)
    add_foreign_key :account_switch_devices, :session_activations, on_delete: :nullify, validate: false unless foreign_key_exists?(:account_switch_devices, :session_activations)
    safety_assured do
      execute <<~SQL.squish
        DELETE FROM account_switch_device_approvals duplicate
        USING account_switch_device_approvals retained
        WHERE duplicate.account_id = retained.account_id
          AND duplicate.target_account_id = retained.target_account_id
          AND duplicate.account_switch_device_id = retained.account_switch_device_id
          AND duplicate.id < retained.id
      SQL
    end
    unless index_exists?(:account_switch_device_approvals, [:account_id, :target_account_id, :account_switch_device_id], name: :index_account_switch_device_approvals_on_request)
      add_index :account_switch_device_approvals,
                [:account_id, :target_account_id, :account_switch_device_id],
                unique: true,
                name: :index_account_switch_device_approvals_on_request,
                algorithm: :concurrently
    end
  end

  def down
    remove_index :account_switch_device_approvals, name: :index_account_switch_device_approvals_on_request
    remove_foreign_key :account_switch_devices, :session_activations
    remove_reference :account_switch_devices, :session_activation
  end
end
