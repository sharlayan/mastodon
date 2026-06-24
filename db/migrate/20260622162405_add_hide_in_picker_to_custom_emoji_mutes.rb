# frozen_string_literal: true

class AddHideInPickerToCustomEmojiMutes < ActiveRecord::Migration[8.1]
  def change
    add_column :custom_emoji_mutes, :hide_in_picker, :boolean, null: false, default: false
  end
end
