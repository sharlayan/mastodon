# frozen_string_literal: true

class CreateAccountSwitchAuthorizations < ActiveRecord::Migration[7.2]
  def change
    create_table :account_switch_authorizations do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :target_account, null: false, foreign_key: { to_table: :accounts, on_delete: :cascade }

      t.timestamps
    end

    add_index :account_switch_authorizations, %i(account_id target_account_id), unique: true, name: :index_account_switch_auths_on_account_and_target
  end
end
