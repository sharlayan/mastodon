# frozen_string_literal: true

class BroadcastStatusUpdateWorker
  include Sidekiq::Worker
  include Redisable

  sidekiq_options queue: 'push', retry: 3

  def perform(status_id)
    status = Status.find(status_id)

    # silenced account updated on public timeline. disabled it
    return if status.account.nil? || status.account.suspended? || status.account.silenced?

    payload = InlineRenderer.render(status, nil, :status)
    return if payload.nil?

    # Always publish to status-specific channel for users currently viewing this status
    redis.publish("timeline:status:#{status.id}", JSON.generate(event: :update, payload: payload))

    # For recent statuses, also broadcast to timelines
    return if status.created_at < 10.minutes.ago

    broadcast_to_all_followers(status, payload)
  rescue ActiveRecord::RecordNotFound
    true
  end

  private

  def broadcast_to_all_followers(status, payload)
    if status.direct_visibility? || status.limited_visibility?
      broadcast_to_direct_timelines(status, payload)
      return
    end

    redis.publish('timeline:public', JSON.generate(event: :update, payload: payload)) if status.public_visibility?

    redis.publish("timeline:#{status.account_id}", JSON.generate(event: :update, payload: payload))

    # if muted user, ignore it
    muted_by_ids = Mute.where(target_account_id: status.account_id).pluck(:account_id)

    list_excluded_ids = ListAccount
      .joins(:list)
      .where(account_id: status.account_id)
      .where(lists: { exclusive: true })
      .pluck('lists.account_id')
      .uniq

    excluded_ids = muted_by_ids + list_excluded_ids

    status.account.followers.where(domain: nil).where.not(id: excluded_ids).select(:id).find_each do |follower|
      redis.publish("timeline:#{follower.id}", JSON.generate(event: :update, payload: payload))
    end
  end

  def broadcast_to_direct_timelines(status, payload)
    recipient_ids = ([status.account_id] + status.mentions.joins(:account).merge(Account.local).pluck(:account_id)).uniq

    recipient_ids.each do |account_id|
      redis.publish("timeline:direct:#{account_id}", JSON.generate(event: :update, payload: payload))
    end
  end
end
