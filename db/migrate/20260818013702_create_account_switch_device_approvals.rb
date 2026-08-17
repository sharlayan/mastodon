# frozen_string_literal: true

class CreateAccountSwitchDeviceApprovals < ActiveRecord::Migration[8.1]
  def change
    create_table :account_switch_device_approvals do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :target_account, null: false, foreign_key: { to_table: :accounts, on_delete: :cascade }
      t.references :account_switch_device, null: false, foreign_key: { on_delete: :cascade }
      t.references :approved_by_device, foreign_key: { to_table: :account_switch_devices, on_delete: :nullify }
      t.inet :request_ip
      t.datetime :expires_at, null: false
      t.datetime :approved_at
      t.datetime :denied_at
      t.timestamps
    end
  end
end
