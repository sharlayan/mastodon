# frozen_string_literal: true

class ActivityPub::Activity::Like < ActivityPub::Activity
  def perform
    original_status = status_from_uri(object_uri)

    return if original_status.nil? || delete_arrived_first?(@json['id'])

    return if misskey_reaction(original_status)

    return if !original_status.account.local? || @account.favourited?(original_status)

    favourite = original_status.favourites.create!(account: @account)

    LocalNotificationWorker.perform_async(original_status.account_id, favourite.id, 'Favourite', 'favourite')
    Trends.statuses.register(original_status)
  end

  def misskey_reaction(original_status)
    raw_name = @json['content'] || @json['_misskey_reaction']

    return false unless raw_name.is_a?(String) && raw_name.present?

    custom_emoji = nil
    name = raw_name

    if /\A:.+:\z/.match?(raw_name)
      name = raw_name.tr(':', '')
      return false if name.blank?

      custom_emoji = process_emoji_tags(name, @json['tag'])

      return false if custom_emoji.nil?
    end

    name, custom_emoji = original_status.accepted_reaction(name, custom_emoji, @account)

    return true if @account.reacted?(original_status, name, custom_emoji)

    reaction = original_status.status_reactions.create!(account: @account, name: name, custom_emoji: custom_emoji)

    LocalNotificationWorker.perform_async(original_status.account_id, reaction.id, 'StatusReaction', 'reaction') if original_status.account.local?
    BroadcastStatusUpdateWorker.perform_async(original_status.id)
    true
  rescue ActiveRecord::RecordInvalid
    true
  end
end
