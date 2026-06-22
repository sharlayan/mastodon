# frozen_string_literal: true

class AddRejectReactionsToCustomEmojiMutes < ActiveRecord::Migration[8.1]
  def change
    return if column_exists?(:custom_emoji_mutes, :reject_reactions)

    add_column :custom_emoji_mutes, :reject_reactions, :boolean, null: false, default: false
  end
end
