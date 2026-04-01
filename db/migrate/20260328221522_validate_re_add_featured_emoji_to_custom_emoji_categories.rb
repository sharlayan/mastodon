# frozen_string_literal: true

class ValidateReAddFeaturedEmojiToCustomEmojiCategories < ActiveRecord::Migration[8.0]
  def change
    validate_foreign_key :custom_emoji_categories, :custom_emojis
  end
end
