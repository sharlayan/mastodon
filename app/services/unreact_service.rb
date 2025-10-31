# frozen_string_literal: true

class UnreactService < BaseService
  include Payloadable

  def call(account, status, emoji)
    name, domain = emoji.split('@')
    custom_emoji = CustomEmoji.find_by(shortcode: name, domain: domain)
    reaction = StatusReaction.find_by(account: account, status: status, name: name, custom_emoji: custom_emoji)
    return if reaction.nil?

    reaction.destroy!
    create_notification(reaction) if !status.account.local? && status.account.activitypub?
    BroadcastStatusUpdateWorker.perform_async(status.id)
    reaction
  end

  private

  def create_notification(reaction)
    status = reaction.status
    ActivityPub::DeliveryWorker.perform_async(build_json(reaction), reaction.account_id, status.account.shared_inbox_url)
  end

  def build_json(reaction)
    json = Oj.dump(serialize_payload(reaction, ActivityPub::UndoEmojiReactionSerializer))
    json.gsub('MisskeyReaction', '_misskey_reaction')
  end
end
