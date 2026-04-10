# frozen_string_literal: true

class AddAvatarDecorationsToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :avatar_decorations, :jsonb, null: false, default: []

    add_column :accounts, :avatar_decorations_blocked, :boolean, null: false, default: false
  end
end
