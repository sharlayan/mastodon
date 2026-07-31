# frozen_string_literal: true

class ActivityPub::Activity::EmojiReact < ActivityPub::Activity
  def perform
    return if DomainBlock.reject_favourite?(@account.domain)

    original_status = status_from_uri(object_uri)
    raw_name = @json['content'].to_s

    return if original_status.nil? || delete_arrived_first?(@json['id'])
    return if raw_name.blank?
    return if ReactionMute.muted?(original_status.account_id, @account)

    custom_emoji = nil
    name = raw_name

    if /\A:.+:\z/.match?(raw_name)
      name = raw_name.tr(':', '')
      return if name.blank?

      custom_emoji = process_emoji_tags(name, @json['tag'])

      return if custom_emoji.nil?
      return if CustomEmojiMute.reaction_muted?(original_status.account_id, custom_emoji.shortcode, custom_emoji.domain)
    end

    name, custom_emoji = original_status.accepted_reaction(name, custom_emoji, @account)

    return if @account.reacted?(original_status, name, custom_emoji)

    reaction = original_status.status_reactions.create!(account: @account, name: name, custom_emoji: custom_emoji)

    LocalNotificationWorker.perform_async(original_status.account_id, reaction.id, 'StatusReaction', 'reaction') if original_status.account.local?

    BroadcastStatusUpdateWorker.perform_async(original_status.id)
  rescue ActiveRecord::RecordInvalid
    nil
  end
end
