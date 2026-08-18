# frozen_string_literal: true

class AddIsSensitiveToCustomEmojis < ActiveRecord::Migration[8.1]
  def up
    return if column_exists?(:custom_emojis, :is_sensitive)

    add_column :custom_emojis, :is_sensitive, :boolean, null: false, default: false
  end

  def down
    remove_column :custom_emojis, :is_sensitive, if_exists: true
  end
end
