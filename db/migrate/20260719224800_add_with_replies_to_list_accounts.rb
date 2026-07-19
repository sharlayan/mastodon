# frozen_string_literal: true

class AddWithRepliesToListAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :list_accounts, :with_replies, :boolean, default: false, null: false
  end
end
