# frozen_string_literal: true

class BroadcastStatusUpdateWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'push', retry: 3

  def perform(status_id)
    status = Status.find(status_id)
    return if status.nil?

    # silenced account updated on public timeline. disabled it
    return if status.account.nil? || status.account.suspended? || status.account.silenced?

    # recent status only
    return if status.created_at < 10.minutes.ago

    payload = InlineRenderer.render(status, nil, :status)
    return if payload.nil?

    if status.mentions.exists?
      broadcast_to_mentioned_users(status, payload)
    else
      broadcast_to_all_followers(status, payload)
    end

    Redis.current.publish("timeline:status:#{status.id}", Oj.dump(event: :update, payload: payload))
  rescue ActiveRecord::RecordNotFound
    true
  end

  private

  def broadcast_to_mentioned_users(status, payload)
    Redis.current.publish("timeline:#{status.account_id}", Oj.dump(event: :update, payload: payload)) if status.account&.local?

    status.mentions.joins(:account).where(accounts: { domain: nil }).pluck(:account_id).compact.each do |account_id|
      Redis.current.publish("timeline:#{account_id}", Oj.dump(event: :update, payload: payload))
    end
  end

  def broadcast_to_all_followers(status, payload)
    Redis.current.publish('timeline:public', Oj.dump(event: :update, payload: payload)) if status.public_visibility?

    Redis.current.publish("timeline:#{status.account_id}", Oj.dump(event: :update, payload: payload))

    # if muted user, ignore it
    muted_by_ids = Mute.where(target_account_id: status.account_id).pluck(:account_id)

    status.account.followers.where(domain: nil).where.not(id: muted_by_ids).select(:id).find_each do |follower|
      Redis.current.publish("timeline:#{follower.id}", Oj.dump(event: :update, payload: payload))
    end
  end
end
