# frozen_string_literal: true

class ReactService < BaseService
  include Authorization
  include Payloadable

  def call(account, status, emoji)
    authorize_with account, status, :react?

    name, domain = emoji.split('@')
    return unless domain.nil? || status.local?

    custom_emoji = CustomEmoji.find_by(shortcode: name, domain: domain)
    reaction = StatusReaction.find_by(account: account, status: status, name: name, custom_emoji: custom_emoji)
    return reaction unless reaction.nil?

    reaction = StatusReaction.create!(account: account, status: status, name: name, custom_emoji: custom_emoji)

    Trends.statuses.register(status)

    create_notification(reaction)
    BroadcastStatusUpdateWorker.perform_async(status.id)
    increment_statistics

    reaction
  end

  private

  def create_notification(reaction)
    status = reaction.status

    if status.account.local?
      LocalNotificationWorker.perform_async(status.account_id, reaction.id, 'StatusReaction', 'reaction')
    elsif status.account.activitypub?
      ActivityPub::DeliveryWorker.perform_async(build_json(reaction), reaction.account_id, status.account.shared_inbox_url)
    end
  end

  def increment_statistics
    ActivityTracker.increment('activity:interactions')
  end

  def build_json(reaction)
    json = Oj.dump(serialize_payload(reaction, ActivityPub::EmojiReactionSerializer))
    json.gsub('MisskeyReaction', '_misskey_reaction')
  end
end
