# frozen_string_literal: true

class MisskeyCompat::UserSerializer
  include RoutingHelper

  def self.serialize(account, detailed: false)
    new.serialize(account, detailed: detailed)
  end

  def serialize(account, detailed: false)
    data = {
      id: account.id.to_s,
      name: account.display_name.presence || account.username,
      username: account.username,
      host: account.local? ? nil : account.domain,
      avatarUrl: full_asset_url(account.unavailable? ? account.avatar.default_url : account.avatar_original_url),
      avatarBlurhash: nil,
      isBot: account.bot?,
      isCat: false,
      isAdmin: false,
      isModerator: false,
      onlineStatus: 'unknown',
      emojis: emojis_map(account.emojis),
    }

    data.merge!(detailed_fields(account)) if detailed
    data
  end

  private

  def detailed_fields(account)
    {
      description: PlainTextFormatter.new(account.note, account.local?).to_s.presence,
      followersCount: account.followers_count,
      followingCount: account.following_count,
      notesCount: account.statuses_count,
      url: account.local? ? account_url(account) : account.url,
      uri: account.local? ? nil : account.uri,
      createdAt: account.created_at&.iso8601,
      updatedAt: account.updated_at&.iso8601,
      isLocked: account.locked?,
      isSilenced: account.silenced?,
      isSuspended: account.suspended?,
      isBot: account.bot?,
      isCat: false,
      publicReactions: true,
      fields: fields_for(account),
      pinnedNoteIds: [],
      pinnedNotes: [],
    }
  end

  def fields_for(account)
    account.fields.map { |field| { name: field.name.to_s, value: PlainTextFormatter.new(field.value.to_s, account.local?).to_s } }
  end

  def emojis_map(custom_emojis)
    custom_emojis.to_h do |emoji|
      [emoji.shortcode, full_asset_url(emoji.image.url)]
    end
  end
end
