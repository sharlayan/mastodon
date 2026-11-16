# frozen_string_literal: true

class MisskeyCompat::EmojiSerializer
  include RoutingHelper

  def self.detailed(emoji)
    new.detailed(emoji)
  end

  def self.detailed_admin(emoji)
    new.detailed_admin(emoji)
  end

  def detailed(emoji)
    {
      id: MisskeyCompat::MiId.encode(emoji.id),
      aliases: Array(emoji.aliases).compact_blank,
      name: emoji.shortcode,
      category: emoji.category&.name,
      host: emoji.domain,
      url: public_url(emoji),
      license: emoji.license,
      isSensitive: emoji.is_sensitive,
      localOnly: emoji.local_only,
      roleIdsThatCanBeUsedThisEmojiAsReaction: [],
    }
  end

  def detailed_admin(emoji)
    {
      id: MisskeyCompat::MiId.encode(emoji.id),
      updatedAt: emoji.updated_at&.iso8601,
      name: emoji.shortcode,
      host: emoji.domain,
      uri: emoji.uri,
      type: emoji.image_content_type,
      aliases: Array(emoji.aliases).compact_blank,
      category: emoji.category&.name,
      publicUrl: public_url(emoji),
      originalUrl: emoji.image_remote_url.presence || public_url(emoji),
      license: emoji.license,
      localOnly: emoji.local_only,
      isSensitive: emoji.is_sensitive,
      roleIdsThatCanBeUsedThisEmojiAsReaction: [],
    }
  end

  private

  def public_url(emoji)
    full_asset_url(emoji.image.url)
  end
end
