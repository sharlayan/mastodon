# frozen_string_literal: true

class ReactService < BaseService
  include Authorization
  include Payloadable
  include Redisable
  include ActivityPub::ReactionDistribution

  def call(account, status, emoji)
    authorize_with account, status, :react?

    return if emoji.blank?

    parts = emoji.to_s.split('@')
    return if parts.size > 2

    name, domain = parts
    return unless domain.nil? || status.local?

    custom_emoji = CustomEmoji.find_by(shortcode: name, domain: domain) if name.present?

    return if domain.present? && custom_emoji.nil?

    return if domain.present? && Setting.reaction_local_emoji_only

    return if status.account.local? && ReactionMute.muted?(status.account_id, account)
    return if status.account.local? && custom_emoji.present? && CustomEmojiMute.reaction_muted?(status.account_id, custom_emoji.shortcode, custom_emoji.domain)

    reaction = StatusReaction.find_by(account: account, status: status, name: name, custom_emoji: custom_emoji)
    return reaction if reaction

    evict_existing_reactions(account, status)

    begin
      reaction = StatusReaction.create!(account: account, status: status, name: name, custom_emoji: custom_emoji)
    rescue ActiveRecord::RecordNotUnique
      return StatusReaction.find_by(account: account, status: status, name: name, custom_emoji: custom_emoji)
    end

    Trends.statuses.register(status)

    create_notification(reaction)
    BroadcastStatusUpdateWorker.perform_async(status.id)
    MisskeyCompat::Streaming.broadcast_reaction(redis, reaction.status, reaction, account, 'reacted')
    increment_statistics

    reaction
  end

  private

  def evict_existing_reactions(account, status)
    return unless account.local?

    target = status.reblog? ? status.reblog : status
    existing = StatusReaction.where(account: account, status: target).order(id: :asc).to_a
    overflow = existing.size + 1 - StatusReactionValidator::LIMIT
    return if overflow <= 0

    existing.first(overflow).each do |reaction|
      UnreactService.new.call(account, target, reaction_emoji_string(reaction))
    end
  end

  def reaction_emoji_string(reaction)
    custom = reaction.custom_emoji
    return reaction.name if custom.nil?

    custom.domain.present? ? "#{reaction.name}@#{custom.domain}" : reaction.name
  end

  def create_notification(reaction)
    status = reaction.status

    LocalNotificationWorker.perform_async(status.account_id, reaction.id, 'StatusReaction', 'reaction') if status.account.local?

    distribute_reaction(reaction)
  end

  def distribute_reaction(reaction)
    distribute_reaction_activity(reaction, build_json(reaction))
  end

  def increment_statistics
    ActivityTracker.increment('activity:interactions')
  end

  def build_json(reaction)
    serialize_payload(reaction, ActivityPub::EmojiReactionSerializer).to_json
  end
end
