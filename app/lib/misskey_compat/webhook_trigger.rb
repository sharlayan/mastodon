# frozen_string_literal: true

class MisskeyCompat::WebhookTrigger
  def self.status_created(status)
    return unless enabled?

    new.dispatch(status_targets(status))
  end

  def self.enabled?
    Setting.misskey_compat_enabled && MisskeyWebhook.any_active?
  end

  def self.follow_created(follow)
    new.dispatch([
                   ['follow', follow.account_id, 'Account', follow.target_account_id],
                   ['followed', follow.target_account_id, 'Account', follow.account_id],
                 ])
  end

  def self.follow_destroyed(follow)
    new.dispatch([['unfollow', follow.account_id, 'Account', follow.target_account_id]])
  end

  def self.status_targets(status)
    targets = []
    targets << ['note', status.account_id] if status.local?
    targets << ['reply', status.in_reply_to_account_id] if status.in_reply_to_account_id.present?

    renoted_account_id = status.reblog&.account_id || status.quote&.quoted_account_id
    targets << ['renote', renoted_account_id] if renoted_account_id.present? && renoted_account_id != status.account_id

    status.mentions.each { |mention| targets << ['mention', mention.account_id] unless mention.silent? }
    targets.map { |event, account_id| [event, account_id, 'Status', status.id] }
  end

  def dispatch(targets)
    return if targets.empty? || !self.class.enabled?

    subscribed = MisskeyWebhook.active.where(account_id: targets.map(&:second).uniq).pluck(:account_id, :events)
    return if subscribed.empty?

    events_by_account = subscribed.each_with_object({}) { |(account_id, events), map| (map[account_id] ||= Set.new).merge(events) }
    targets.uniq.each do |event, account_id, object_type, object_id|
      next unless events_by_account[account_id]&.include?(event)

      MisskeyCompatWebhookEventWorker.perform_async(event, account_id.to_s, object_type, object_id.to_s)
    end
  end
end
