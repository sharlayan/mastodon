# frozen_string_literal: true

class AddMfmToAccounts < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def up
    add_column :accounts, :mfm, :boolean, default: false, null: false unless column_exists?(:accounts, :mfm)

    Account.unscoped.in_batches do |batch|
      batch.each do |account|
        mfm = MfmDetector.contains_mfm?(account.note) ||
              account.fields.any? { |field| MfmDetector.contains_mfm?(field.value) }
        account.update_column(:mfm, mfm) if mfm
      end
    end
  end

  def down
    remove_column :accounts, :mfm
  end
end
