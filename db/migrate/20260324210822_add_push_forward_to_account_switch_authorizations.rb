# frozen_string_literal: true

class AddPushForwardToAccountSwitchAuthorizations < ActiveRecord::Migration[7.2]
  def change
    return if column_exists?(:account_switch_authorizations, :push_forward)

    add_column :account_switch_authorizations, :push_forward, :boolean, default: false, null: false
  end
end
