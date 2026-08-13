# frozen_string_literal: true

module ActivityPub::ReactionDistribution
  def distribute_reaction_activity(reaction, json)
    return unless reaction.account.local?

    status = reaction.status
    return if status.local_only?

    case status.visibility.to_sym
    when :public, :unlisted
      target_inbox = status.account.local? || Sharlayan::SilentInteractionDelivery.suppressed_for?(status.account) ? '' : status.account.preferred_inbox_url
      ActivityPub::ReactionsDistributionWorker.perform_async(json, reaction.account_id, target_inbox)
    when :private
      reaction_private_inboxes(status).each do |inbox_url|
        ActivityPub::DeliveryWorker.perform_async(json, reaction.account_id, inbox_url)
      end
    when :direct, :limited
      reaction_direct_inboxes(status).each do |inbox_url|
        ActivityPub::DeliveryWorker.perform_async(json, reaction.account_id, inbox_url)
      end
    end
  end

  private

  def reaction_direct_inboxes(status)
    inboxes = status.active_mentions.includes(:account).map(&:account).select { |account| account.activitypub? && !Sharlayan::SilentInteractionDelivery.suppressed_for?(account) }.map(&:preferred_inbox_url)
    inboxes << status.account.preferred_inbox_url if status.account.activitypub? && !Sharlayan::SilentInteractionDelivery.suppressed_for?(status.account)
    inboxes.uniq
  end

  def reaction_private_inboxes(status)
    inboxes = reaction_direct_inboxes(status)
    inboxes.concat(status.account.followers.inboxes) if status.account.local?
    inboxes.uniq
  end
end
