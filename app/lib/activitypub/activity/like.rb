# frozen_string_literal: true

class ActivityPub::Activity::Like < ActivityPub::Activity
  def perform
    return if DomainBlock.reject_favourite?(@account.domain)

    original_status = status_from_uri(object_uri)

    return if original_status.nil? || delete_arrived_first?(@json['id'])

    return if misskey_reaction

    return if !original_status.account.local? || @account.favourited?(original_status)

    favourite = original_status.favourites.create!(account: @account)

    LocalNotificationWorker.perform_async(original_status.account_id, favourite.id, 'Favourite', 'favourite')
    Trends.statuses.register(original_status)
  end

  # custom function for emojireact
  def misskey_reaction
    original_status = status_from_uri(object_uri)
    name = @json['content'] || @json['_misskey_reaction']

    return false if name.nil?

    return true if ReactionMute.muted?(original_status.account_id, @account)

    if /^:.*:$/.match?(name)
      name.delete! ':'
      custom_emoji = process_emoji_tags(name, @json['tag'])

      # invalid custom emoji, treat it as a regular like
      return false if custom_emoji.nil?

      return true if CustomEmojiMute.reaction_muted?(original_status.account_id, custom_emoji.shortcode, custom_emoji.domain)
    end

    return true if @account.reacted?(original_status, name, custom_emoji)

    reaction = original_status.status_reactions.create!(account: @account, name: name, custom_emoji: custom_emoji)

    LocalNotificationWorker.perform_async(original_status.account_id, reaction.id, 'StatusReaction', 'reaction') if original_status.account.local?
    BroadcastStatusUpdateWorker.perform_async(original_status.id)
    true
  # account tried to react with disabled custom emoji. Returning true to discard activity.
  rescue ActiveRecord::RecordInvalid
    true
  end
end
