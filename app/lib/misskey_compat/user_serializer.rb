# frozen_string_literal: true

class MisskeyCompat::UserSerializer
  include RoutingHelper

  def self.serialize(account, detailed: false, viewer: nil, me_user: nil)
    new.serialize(account, detailed: detailed, viewer: viewer, me_user: me_user)
  end

  def serialize(account, detailed: false, viewer: nil, me_user: nil)
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

    if detailed
      data.merge!(detailed_fields(account))
      data.merge!(viewer_fields(account, viewer)) if viewer && viewer.id != account.id
      data.merge!(me_fields(me_user)) if me_user && me_user.account_id == account.id
    end

    data
  end

  private

  def viewer_fields(account, viewer)
    {
      isFollowing: viewer.following?(account),
      isFollowed: viewer.followed_by?(account),
      hasPendingFollowRequestFromYou: viewer.requested?(account),
      hasPendingFollowRequestToYou: account.requested?(viewer),
      isBlocking: viewer.blocking?(account),
      isBlocked: account.blocking?(viewer),
      isMuted: viewer.muting?(account),
      isRenoteMuted: viewer.muting_reblogs?(account),
    }
  end

  def me_fields(user)
    account = user.account
    ff_visibility = account.hide_collections? ? 'followers' : 'public'

    {
      alwaysMarkNsfw: user.settings['default_sensitive'] || false,
      carefulBot: false,
      autoAcceptFollowed: user.settings['auto_accept_followed'] || false,
      noCrawle: user.settings['noindex'] || false,
      preventAiLearning: false,
      isExplorable: account.discoverable?,
      hideOnlineStatus: false,
      ffVisibility: ff_visibility,
      followingVisibility: ff_visibility,
      followersVisibility: ff_visibility,
      mutedWords: parse_muted_words(user.settings['misskey_muted_words']),
      hardMutedWords: parse_muted_words(user.settings['misskey_hard_muted_words']),
      mutedInstances: account.domain_mutes.pluck(:domain),
      mutedEmojis: MisskeyCompat::MutedEmojiConverter.to_misskey(account),
    }
  end

  def parse_muted_words(raw)
    parsed = JSON.parse(raw.to_s)
    parsed.is_a?(Array) ? parsed : []
  rescue JSON::ParserError
    []
  end

  def detailed_fields(account)
    {
      description: PlainTextFormatter.new(account.note, account.local?).to_s.presence,
      followersCount: account.followers_count,
      followingCount: account.following_count,
      notesCount: account.statuses_count,
      url: account.local? ? nil : account.url,
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
