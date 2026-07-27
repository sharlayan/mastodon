# frozen_string_literal: true

class AddMfmToAccounts < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  # Dummy class, to make migration possible across version changes
  class Account < ApplicationRecord; end

  def up
    add_column :accounts, :mfm, :boolean, default: false, null: false unless column_exists?(:accounts, :mfm)

    Account.reset_column_information

    Account.unscoped.in_batches do |batch|
      batch.each do |account|
        mfm = MfmDetector.contains_mfm?(account[:note]) ||
              field_values(account).any? { |value| MfmDetector.contains_mfm?(value) }
        account.update_column(:mfm, mfm) if mfm
      end
    end
  end

  def down
    remove_column :accounts, :mfm
  end

  private

  def field_values(account)
    fields = account[:fields]
    return [] unless fields.is_a?(Array)

    fields.filter_map { |field| field['value'] if field.is_a?(Hash) }
  end
end
