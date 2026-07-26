# frozen_string_literal: true

class Api::MisskeyCompat::EmojisController < Api::MisskeyCompat::BaseController
  def index
    render json: { emojis: CustomEmoji.local.enabled.includes(:category).map { |emoji| serialize(emoji) } }
  end

  def show
    name = params[:name].to_s.delete_prefix(':').delete_suffix(':')
    shortcode, _, domain = name.rpartition('@')
    shortcode = name if shortcode.blank?
    emoji = CustomEmoji.includes(:category).find_by(shortcode: shortcode, domain: domain.presence)
    emoji ||= CustomEmoji.includes(:category).find_by(shortcode: name, domain: nil)

    return render_error('No such emoji', 'NO_SUCH_EMOJI', 404) if emoji.nil?

    render json: serialize(emoji)
  end

  private

  def serialize(emoji)
    {
      id: MisskeyCompat::MiId.encode(emoji.id),
      aliases: Array(emoji.aliases).compact_blank,
      name: emoji.shortcode,
      category: emoji.category&.name,
      host: emoji.domain,
      url: full_asset_url(emoji.image.url),
      license: emoji.license,
      isSensitive: emoji.is_sensitive,
      localOnly: emoji.local_only,
      roleIdsThatCanBeUsedThisEmojiAsReaction: [],
    }
  end
end
