# frozen_string_literal: true

class Api::MisskeyCompat::EmojisController < Api::MisskeyCompat::BaseController
  def index
    render json: { emojis: CustomEmoji.listed.includes(:category).map { |emoji| serialize(emoji) } }
  end

  private

  def serialize(emoji)
    {
      aliases: Array(emoji.aliases).compact_blank,
      name: emoji.shortcode,
      category: emoji.category&.name,
      url: full_asset_url(emoji.image.url),
      isSensitive: false,
      localOnly: false,
      roleIdsThatCanBeUsedThisEmojiAsReaction: [],
    }
  end
end
