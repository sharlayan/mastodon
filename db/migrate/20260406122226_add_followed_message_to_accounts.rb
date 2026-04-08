# frozen_string_literal: true

class AddFollowedMessageToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :followed_message, :string, limit: 256
  end
end
