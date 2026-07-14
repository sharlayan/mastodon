# frozen_string_literal: true

class AddMisskeyProfileFieldsToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :location, :string, limit: 256
    add_column :accounts, :birthday, :string, limit: 32
  end
end
