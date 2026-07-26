# frozen_string_literal: true

class AddSensitivityAndLocalOnlyToCustomEmojis < ActiveRecord::Migration[8.1]
  def change
    add_column :custom_emojis, :is_sensitive, :boolean, default: false, null: false
    add_column :custom_emojis, :local_only, :boolean, default: false, null: false
  end
end
