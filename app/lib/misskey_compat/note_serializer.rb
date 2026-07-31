# frozen_string_literal: true

class MisskeyCompat::NoteSerializer
  include RoutingHelper

  VISIBILITY_MAP = {
    'public' => 'public',
    'unlisted' => 'home',
    'private' => 'followers',
    'direct' => 'specified',
    'limited' => 'specified',
  }.freeze

  def self.serialize(status, current_account: nil, embed_relations: true, context: nil)
    new.serialize(status, current_account: current_account, embed_relations: embed_relations, context: context)
  end

  def serialize(status, current_account: nil, embed_relations: true, context: nil)
    @context = context || MisskeyCompat::SerializationContext.new(current_account: current_account)
    @current_account = @context.current_account

    return serialize_renote(status, embed_relations: embed_relations) if pure_renote?(status)

    emojis = {}
    reaction_emojis = {}
    reactions, my_reaction = reactions_for(status, reaction_emojis, emojis)
    merge_text_emojis(status, emojis)
    mentions = load_mentions(status)
    media = status.ordered_media_attachments

    {
      id: MisskeyCompat::MiId.encode(status.id),
      createdAt: status.created_at.iso8601,
      text: text_for(status, mentions),
      cw: status.spoiler_text.presence,
      userId: MisskeyCompat::MiId.encode(status.account_id),
      user: @context.user(status.account),
      visibility: VISIBILITY_MAP.fetch(status.visibility, 'public'),
      localOnly: status.local_only?,
      reactionAcceptance: status.reaction_acceptance,
      reactions: reactions,
      reactionEmojis: reaction_emojis,
      myReaction: my_reaction,
      renoteCount: status.reblogs_count,
      repliesCount: status.replies_count,
      replyId: MisskeyCompat::MiId.encode(status.in_reply_to_id),
      reply: embed_relations ? embedded_note(status.thread) : nil,
      renoteId: quoted_id(status),
      renote: embed_relations ? embedded_note(quoted_status(status)) : nil,
      isHidden: false,
      mentions: mentions.map { |m| MisskeyCompat::MiId.encode(m.account_id) },
      visibleUserIds: [],
      fileIds: media.map { |m| MisskeyCompat::MiId.encode(m.drive_file_id || m.id) },
      files: media.map { |m| MisskeyCompat::DriveFileSerializer.serialize(m, sensitive: status.sensitive?) },
      tags: status.tags.map(&:name),
      poll: poll_for(status),
      emojis: emojis,
      uri: status.local? ? nil : status.uri,
      url: status.local? ? nil : (status.url || ActivityPub::TagManager.instance.url_for(status)),
    }
  end

  private

  def pure_renote?(status)
    status.reblog? && status.spoiler_text.blank? && status.text.blank? && status.ordered_media_attachments.empty?
  end

  def serialize_renote(status, embed_relations: true)
    {
      id: MisskeyCompat::MiId.encode(status.id),
      createdAt: status.created_at.iso8601,
      text: nil,
      cw: nil,
      userId: MisskeyCompat::MiId.encode(status.account_id),
      user: @context.user(status.account),
      visibility: VISIBILITY_MAP.fetch(status.visibility, 'public'),
      renoteId: MisskeyCompat::MiId.encode(status.reblog_of_id),
      renote: embed_relations ? serialize(status.reblog, embed_relations: false, context: @context) : nil,
      reactions: {},
      reactionEmojis: {},
      renoteCount: status.reblogs_count,
      repliesCount: status.replies_count,
      emojis: {},
    }
  end

  def quoted_status(status)
    status.quote&.quoted_status
  end

  def embedded_note(status)
    return nil if status.nil?
    return nil unless StatusPolicy.new(@current_account, status).show?

    serialize(status, embed_relations: false, context: @context)
  rescue Mastodon::NotPermittedError
    nil
  end

  def load_mentions(status)
    if status.association(:mentions).loaded?
      status.mentions.to_a
    else
      status.mentions.includes(:account).to_a
    end
  end

  def text_for(status, mentions)
    text = PlainTextFormatter.new(status.text, status.local?).to_s.presence
    text && qualify_mentions(text, mentions)
  end

  def qualify_mentions(text, mentions)
    mentions.each do |mention|
      account = mention.account
      next if account.nil?

      host = account.local? ? Rails.configuration.x.local_domain : account.domain
      next if host.blank?

      text = qualify_local_mention_port(text, account.username, host) if account.local?
      text = text.gsub(/@#{Regexp.escape(account.username)}(?![A-Za-z0-9_@])/i) { |m| "#{m}@#{host}" }
    end

    text
  end

  def qualify_local_mention_port(text, username, host)
    host_without_port = host.sub(/:\d+\z/, '')
    return text if host_without_port == host

    text.gsub(/(@#{Regexp.escape(username)})@#{Regexp.escape(host_without_port)}(?![A-Za-z0-9_@.:-])/i) do
      "#{Regexp.last_match(1)}@#{host}"
    end
  end

  def quoted_id(status)
    return MisskeyCompat::MiId.encode(status.reblog_of_id) if status.reblog?

    MisskeyCompat::MiId.encode(status.quote&.quoted_status_id)
  end

  def reactions_for(status, reaction_emojis, emojis)
    reactions = {}
    my_reaction = nil

    @context.reactions_for(status).each do |reaction|
      custom = reaction.custom_emoji

      if custom.present?
        host = custom.domain.presence
        suffix = host ? "#{reaction.name}@#{host}" : "#{reaction.name}@."
        key = ":#{suffix}:"
        url = full_asset_url(custom.image.url)
        reaction_emojis["#{reaction.name}@#{host}"] = url if host
        emojis[suffix] ||= url
        emojis[reaction.name] ||= url if host.nil?
      else
        key = reaction.name
      end

      reactions[key] = reaction.count
      my_reaction = key if reaction_me?(reaction)
    end

    [reactions, my_reaction]
  end

  def reaction_me?(reaction)
    reaction.respond_to?(:me) && ActiveModel::Type::Boolean.new.cast(reaction.me)
  end

  def merge_text_emojis(status, emojis)
    status.emojis.each do |emoji|
      emojis[emoji.shortcode] ||= full_asset_url(emoji.image.url)
    end
  end

  def poll_for(status)
    poll = status.preloadable_poll
    return nil if poll.nil?

    own_votes = @context.own_votes(poll)

    {
      multiple: poll.multiple?,
      expiresAt: poll.expires_at&.iso8601,
      choices: poll.loaded_options.map.with_index do |option, index|
        { text: option.title, votes: option.votes_count || 0, isVoted: own_votes.include?(index) }
      end,
    }
  end
end
