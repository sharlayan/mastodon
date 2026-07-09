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

  def self.serialize(status, current_account: nil)
    new.serialize(status, current_account: current_account)
  end

  def serialize(status, current_account: nil)
    return serialize_renote(status, current_account: current_account) if pure_renote?(status)

    emojis = {}
    reactions, my_reaction = reactions_for(status, current_account, emojis)
    merge_text_emojis(status, emojis)
    @current_account = current_account

    {
      id: status.id.to_s,
      createdAt: status.created_at.iso8601,
      text: text_for(status),
      cw: status.spoiler_text.presence,
      userId: status.account_id.to_s,
      user: MisskeyCompat::UserSerializer.serialize(status.account),
      visibility: VISIBILITY_MAP.fetch(status.visibility, 'public'),
      localOnly: status.local_only?,
      reactionAcceptance: nil,
      reactions: reactions,
      reactionEmojis: {},
      myReaction: my_reaction,
      renoteCount: status.reblogs_count,
      repliesCount: status.replies_count,
      replyId: status.in_reply_to_id&.to_s,
      renoteId: quoted_id(status),
      isHidden: false,
      mentions: status.mentions.map { |m| m.account_id.to_s },
      visibleUserIds: [],
      fileIds: status.ordered_media_attachments.map { |m| m.id.to_s },
      files: status.ordered_media_attachments.map { |m| MisskeyCompat::DriveFileSerializer.serialize(m) },
      tags: status.tags.map(&:name),
      poll: poll_for(status),
      emojis: emojis,
      uri: status.local? ? nil : status.uri,
      url: status.local? ? ActivityPub::TagManager.instance.url_for(status) : status.url,
    }
  end

  private

  def pure_renote?(status)
    status.reblog? && status.spoiler_text.blank? && status.text.blank? && status.ordered_media_attachments.empty?
  end

  def serialize_renote(status, current_account:)
    {
      id: status.id.to_s,
      createdAt: status.created_at.iso8601,
      text: nil,
      cw: nil,
      userId: status.account_id.to_s,
      user: MisskeyCompat::UserSerializer.serialize(status.account),
      visibility: VISIBILITY_MAP.fetch(status.visibility, 'public'),
      renoteId: status.reblog_of_id.to_s,
      renote: serialize(status.reblog, current_account: current_account),
      reactions: {},
      reactionEmojis: {},
      renoteCount: status.reblogs_count,
      repliesCount: status.replies_count,
      emojis: {},
    }
  end

  def text_for(status)
    PlainTextFormatter.new(status.text, status.local?).to_s.presence
  end

  def quoted_id(status)
    return status.reblog_of_id.to_s if status.reblog?

    status.quote&.quoted_status_id&.to_s
  end

  def reactions_for(status, current_account, emojis)
    reactions = {}
    my_reaction = nil

    status.reactions(current_account&.id).each do |reaction|
      custom = reaction.custom_emoji

      if custom.present?
        suffix = custom.domain.present? ? "#{reaction.name}@#{custom.domain}" : reaction.name
        key = ":#{suffix}:"
        emojis[suffix] = full_asset_url(custom.image.url)
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

    own_votes = @current_account ? poll.own_votes(@current_account) : []

    {
      multiple: poll.multiple?,
      expiresAt: poll.expires_at&.iso8601,
      choices: poll.loaded_options.map.with_index do |option, index|
        { text: option.title, votes: option.votes_count || 0, isVoted: own_votes.include?(index) }
      end,
    }
  end
end
