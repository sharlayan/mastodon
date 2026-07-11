# frozen_string_literal: true

class UnreactService < BaseService
  include Payloadable
  include Redisable
  include ActivityPub::ReactionDistribution

  def call(account, status, emoji)
    name, domain = emoji.to_s.split('@')
    custom_emoji = CustomEmoji.find_by(shortcode: name, domain: domain)
    reaction = StatusReaction.find_by!(account: account, status: status, name: name, custom_emoji: custom_emoji)
    reaction.destroy!
    distribute_undo_reaction(reaction)
    BroadcastStatusUpdateWorker.perform_async(status.id)
    MisskeyCompat::Streaming.broadcast_reaction(redis, status, reaction, account, 'unreacted')
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
