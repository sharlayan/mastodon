# frozen_string_literal: true

class CreateAccountSwitchDevices < ActiveRecord::Migration[8.1]
  def change
    create_table :account_switch_devices do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :token_digest, null: false
      t.inet :first_seen_ip
      t.inet :last_seen_ip
      t.string :user_agent
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.datetime :trusted_at
      t.datetime :revoked_at
      t.timestamps
    end

    add_index :account_switch_devices, [:account_id, :token_digest], unique: true, name: :index_account_switch_devices_on_account_and_token
  end
end
