# frozen_string_literal: true

class BroadcastStatusUpdateWorker
  include Sidekiq::Worker
  include Redisable

  sidekiq_options queue: 'push', retry: 3

  def perform(status_id)
    status = Status.find(status_id)

    # silenced account updated on public timeline. disabled it
    return if status.account.nil? || status.account.suspended? || status.account.silenced?

    message = JSON.generate(event: 'status.reaction', payload: reaction_payload(status.proper))

    # Always publish to status-specific channel for users currently viewing this status
    redis.publish("timeline:status:#{status.id}", message)

    # Avoid bumping stale posts back into home/public timelines when they merely
    # receive a new reaction; only refresh the status-specific channel for those.
    broadcast_to_all_followers(status, message) unless status_too_old?(status)
  rescue ActiveRecord::RecordNotFound
    true
  end

  private

  def reaction_payload(status)
    reactions = status.reactions

    {
      id: status.id.to_s,
      reactions_count: status.reactions_count,
      reactions: ActiveModelSerializers::SerializableResource.new(
        reactions,
        each_serializer: REST::StreamingReactionSerializer
      ).as_json,
    }
  end

  def status_too_old?(status)
    status.created_at < 7.days.ago
  end

  def broadcast_to_all_followers(status, message)
    if status.direct_visibility? || status.limited_visibility?
      broadcast_to_direct_timelines(status, message)
      return
    end

    redis.publish('timeline:public', message) if status.public_visibility?

    redis.publish("timeline:#{status.account_id}", message)

    # if muted user, ignore it
    muted_by_ids = Mute.where(target_account_id: status.account_id).pluck(:account_id)

    list_excluded_ids = ListAccount
      .joins(:list)
      .where(account_id: status.account_id)
      .where(lists: { exclusive: true })
      .pluck('lists.account_id')
      .uniq

    excluded_ids = muted_by_ids + list_excluded_ids

    status.account.followers.where(domain: nil).where.not(id: excluded_ids).select(:id).reorder(nil).find_each do |follower|
      redis.publish("timeline:#{follower.id}", message)
    end
  end

  def broadcast_to_direct_timelines(status, message)
    recipient_ids = ([status.account_id] + status.mentions.joins(:account).merge(Account.local).pluck(:account_id)).uniq

    recipient_ids.each do |account_id|
      redis.publish("timeline:direct:#{account_id}", message)
    end
  end
end
