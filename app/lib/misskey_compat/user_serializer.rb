# frozen_string_literal: true

class MisskeyCompat::UserSerializer
  include RoutingHelper

  def self.serialize(account, detailed: false, viewer: nil, me_user: nil, context: nil, relationships: nil)
    new.serialize(account, detailed: detailed, viewer: viewer, me_user: me_user, context: context, relationships: relationships)
  end

  def serialize(account, detailed: false, viewer: nil, me_user: nil, context: nil, relationships: nil)
    @context = context
    data = {
      id: MisskeyCompat::MiId.encode(account.id),
      name: account.display_name.presence || account.username,
      username: account.username,
      host: account.local? ? nil : account.domain,
      avatarUrl: full_asset_url(account.unavailable? ? account.avatar.default_url : account.avatar_original_url),
      avatarBlurhash: nil,
      isBot: account.bot?,
      isCat: Setting.cat_enabled && account.is_cat?,
      isAdmin: false,
      isModerator: false,
      onlineStatus: 'unknown',
      emojis: emojis_map(account.emojis),
      avatarDecorations: avatar_decorations_for(account),
      instance: instance_info(account),
    }

    if detailed
      data.merge!(detailed_fields(account, viewer))
      data.merge!(viewer_fields(account, viewer, relationships)) if viewer && viewer.id != account.id
      data.merge!(me_fields(me_user)) if me_user && me_user.account_id == account.id
    end

    data
  end

  private

  def viewer_fields(account, viewer, relationships)
    return preloaded_viewer_fields(account, relationships) if relationships

    {
      isFollowing: viewer.following?(account),
      isFollowed: viewer.followed_by?(account),
      hasPendingFollowRequestFromYou: viewer.requested?(account),
      hasPendingFollowRequestToYou: account.requested?(viewer),
      isBlocking: viewer.blocking?(account),
      isBlocked: account.blocking?(viewer),
      isMuted: viewer.muting?(account),
      isRenoteMuted: viewer.muting_reblogs?(account),
      memo: viewer.account_notes.find_by(target_account_id: account.id)&.comment,
    }
  end

  def preloaded_viewer_fields(account, relationships)
    following = relationships.following[account.id]

    {
      isFollowing: following.present?,
      isFollowed: relationships.followed_by[account.id] || false,
      hasPendingFollowRequestFromYou: relationships.requested[account.id].present?,
      hasPendingFollowRequestToYou: relationships.requested_by[account.id].present?,
      isBlocking: relationships.blocking[account.id] || false,
      isBlocked: relationships.blocked_by[account.id] || false,
      isMuted: relationships.muting[account.id].present?,
      isRenoteMuted: following.present? && following[:reblogs] == false,
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
      preventAiLearning: user.settings['prevent_ai_learning'] || false,
      isExplorable: account.discoverable?,
      hideOnlineStatus: user.settings['hide_online_status'] || false,
      ffVisibility: ff_visibility,
      followingVisibility: ff_visibility,
      followersVisibility: ff_visibility,
      followedMessage: account.followed_message.presence,
      location: account.location.presence,
      birthday: account.birthday.presence,
      lang: user.settings['default_language'].presence,
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

  def detailed_fields(account, viewer)
    ff_visibility = account.hide_collections? ? 'followers' : 'public'
    pinned_note_ids, pinned_notes = pinned_notes_for(account, viewer)
    pinned_page_id, pinned_page = pinned_page_for(account, viewer)

    {
      description: PlainTextFormatter.new(account.note, account.local?).to_s.presence,
      followersCount: account.followers_count,
      followingCount: account.following_count,
      notesCount: account.statuses_count,
      url: account.local? ? nil : account.url,
      uri: account.local? ? nil : account.uri,
      movedTo: account.moved_to_account&.uri,
      alsoKnownAs: nil,
      createdAt: account.created_at&.iso8601,
      updatedAt: account.updated_at&.iso8601,
      lastFetchedAt: nil,
      bannerUrl: header_url(account),
      bannerBlurhash: nil,
      isLocked: account.locked?,
      isSilenced: account.silenced?,
      isSuspended: account.suspended?,
      isBot: account.bot?,
      isCat: Setting.cat_enabled && account.is_cat?,
      publicReactions: public_reactions?(account),
      fields: fields_for(account),
      verifiedLinks: verified_links_for(account),
      followingVisibility: ff_visibility,
      followersVisibility: ff_visibility,
      roles: roles_for(account),
      memo: nil,
      chatScope: 'none',
      canChat: false,
      pinnedNoteIds: pinned_note_ids,
      pinnedNotes: pinned_notes,
      pinnedPageId: pinned_page_id,
      pinnedPage: pinned_page,
    }
  end

  def pinned_notes_for(account, viewer)
    statuses = account.pinned_statuses.where(visibility: [:public, :unlisted]).to_a
    return [[], []] if statuses.empty?

    Status.preload_cacheable_associations(statuses)
    context = MisskeyCompat::SerializationContext.for(statuses, current_account: viewer)

    [
      statuses.map { |status| MisskeyCompat::MiId.encode(status.id) },
      statuses.map { |status| MisskeyCompat::NoteSerializer.serialize(status, context: context) },
    ]
  end

  def pinned_page_for(account, viewer)
    return [nil, nil] unless Setting.pages_enabled

    page = account.pages.find_by(is_main: true)
    return [nil, nil] if page.nil? || !page.public_visibility?

    [MisskeyCompat::MiId.encode(page.id), MisskeyCompat::PageSerializer.serialize(page, current_account: viewer)]
  end

  def verified_links_for(account)
    account.fields.filter_map do |field|
      next unless field.verified?

      PlainTextFormatter.new(field.value.to_s, account.local?).to_s
    end
  end

  def roles_for(account)
    role = account.local? ? account.user&.role : nil
    return [] if role.nil? || role.everyone? || !role.highlighted?

    [
      {
        id: MisskeyCompat::MiId.encode(role.id),
        name: role.name,
        color: role.color.presence,
        iconUrl: nil,
        description: '',
        isModerator: role.can?(*UserRole::Flags::CATEGORIES[:moderation]),
        isAdministrator: role.can?(:administrator),
        displayOrder: role.position,
      },
    ]
  end

  def header_url(account)
    return nil if account.unavailable?
    return nil if account.header_file_name.blank?

    full_asset_url(account.header_static_url)
  end

  def public_reactions?(account)
    return true unless account.local? && account.user

    account.user.settings['show_reactions'] != false
  end

  def instance_info(account)
    return nil if account.local?

    domain = account.domain
    return nil if domain.blank?

    if @context
      @context.instance_info(domain) { build_instance_info(domain) }
    else
      build_instance_info(domain)
    end
  end

  def build_instance_info(domain)
    metadata = InstanceMetadata.cached_by_domain(domain)
    favicon = metadata&.favicon_url_with_fallback || "https://#{domain}/favicon.ico"

    {
      name: metadata&.instance_name_with_fallback || domain,
      softwareName: metadata&.software,
      softwareVersion: metadata&.version,
      iconUrl: favicon,
      faviconUrl: favicon,
      themeColor: metadata&.theme_color_with_fallback,
    }
  end

  def avatar_decorations_for(account)
    return [] unless Setting.avatar_decorations_enabled
    return [] if account.avatar_decorations_blocked || account.avatar_decorations.blank?

    decoration_ids = account.avatar_decorations.filter_map { |config| config['id'] }
    return [] if decoration_ids.empty?

    decorations_by_id = AvatarDecoration.find_many_cached(decoration_ids).index_by(&:id)

    account.avatar_decorations.filter_map do |config|
      decoration = decorations_by_id[config['id']]
      next if decoration.nil?

      {
        id: MisskeyCompat::MiId.encode(decoration.id),
        url: full_asset_url(decoration.image_url),
        angle: config['angle'] || 0.0,
        flipH: config['flip_h'] || false,
        offsetX: config['offset_x'] || 0.0,
        offsetY: config['offset_y'] || 0.0,
      }
    end
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
