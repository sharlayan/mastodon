# frozen_string_literal: true

class ReAddFeaturedEmojiToCustomEmojiCategories < ActiveRecord::Migration[8.0]
  def up
    add_column :custom_emoji_categories, :featured_emoji_id, :bigint, null: true unless column_exists?(:custom_emoji_categories, :featured_emoji_id)

    add_foreign_key :custom_emoji_categories, :custom_emojis, column: :featured_emoji_id, on_delete: :nullify, validate: false unless foreign_key_exists?(:custom_emoji_categories, :custom_emojis, column: :featured_emoji_id)
  end

  def down
    remove_foreign_key :custom_emoji_categories, :custom_emojis, column: :featured_emoji_id if foreign_key_exists?(:custom_emoji_categories, :custom_emojis, column: :featured_emoji_id)
    remove_column :custom_emoji_categories, :featured_emoji_id if column_exists?(:custom_emoji_categories, :featured_emoji_id)
  end
end
