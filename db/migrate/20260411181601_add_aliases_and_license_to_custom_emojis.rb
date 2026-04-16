# frozen_string_literal: true

class AddAliasesAndLicenseToCustomEmojis < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_column :custom_emojis, :aliases, :text, array: true, default: [], null: false
    add_column :custom_emojis, :license, :text

    add_index :custom_emojis, :aliases, using: :gin, algorithm: :concurrently
  end
end
