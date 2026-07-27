# frozen_string_literal: true

class RemoveUnicodeFavoriteEmojis < ActiveRecord::Migration[7.2]
  # Dummy class, to make migration possible across version changes
  class FavoriteEmoji < ApplicationRecord; end

  def up
    FavoriteEmoji.reset_column_information

    # Remove all unicode favorite emojis, then repack positions per account
    FavoriteEmoji.where(emoji_type: 'unicode').delete_all

    FavoriteEmoji.select(:account_id).distinct.each do |row|
      FavoriteEmoji.where(account_id: row.account_id)
        .order(:position)
        .each_with_index { |fe, i| fe.update_columns(position: i) }
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
