# frozen_string_literal: true

class UnreactService < BaseService
  include Payloadable

  def call(account, status, emoji)
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
    return unless reaction.account.local?

    status = reaction.status
    target_inbox = status.account.local? ? '' : (status.account.shared_inbox_url || status.account.inbox_url)
    ActivityPub::ReactionsDistributionWorker.perform_async(build_json(reaction), reaction.account_id, target_inbox)
  end

  def build_json(reaction)
    json = serialize_payload(reaction, ActivityPub::UndoEmojiReactionSerializer).to_json
    json.gsub('MisskeyReaction', '_misskey_reaction')
  end
end
