# frozen_string_literal: true

class AddIsCatToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :is_cat, :boolean, null: false, default: false
  end
end
