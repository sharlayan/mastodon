# frozen_string_literal: true

class UnreactService < BaseService
  include Payloadable
  include ActivityPub::ReactionDistribution

  def call(account, status, emoji)
    return if emoji.blank?

    name, domain = emoji.split('@')
    custom_emoji = CustomEmoji.find_by(shortcode: name, domain: domain)
    reaction = StatusReaction.find_by(account: account, status: status, name: name, custom_emoji: custom_emoji)
    return if reaction.nil?

    reaction.destroy!
    distribute_undo_reaction(reaction)
    BroadcastStatusUpdateWorker.perform_async(status.id)
    reaction
  end

  private

  def distribute_undo_reaction(reaction)
    distribute_reaction_activity(reaction, build_json(reaction))
  end

  def build_json(reaction)
    serialize_payload(reaction, ActivityPub::UndoEmojiReactionSerializer).to_json
  end
end
