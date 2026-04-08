# frozen_string_literal: true

module ActivityPub::ReactionDistribution
  def distribute_reaction_activity(reaction, json)
    return unless reaction.account.local?

    status = reaction.status

    if status.public_visibility?
      target_inbox = status.account.local? ? '' : (status.account.shared_inbox_url || status.account.inbox_url)
      ActivityPub::ReactionsDistributionWorker.perform_async(json, reaction.account_id, target_inbox)
    elsif status.account.activitypub?
      # For non-public statuses, only notify the status author directly
      # to avoid leaking reaction info to servers that cannot see the post
      ActivityPub::DeliveryWorker.perform_async(json, reaction.account_id, status.account.inbox_url)
    end
  end
end
