# frozen_string_literal: true

module Sharlayan::FeedManagerExtensions
  def filter(timeline_type, status, receiver)
    return super unless timeline_type == :antenna

    filter_from_antenna?(status, receiver.account_id, build_crutches(receiver.account_id, [status])) ? :filter : nil
  end

  def filter_home_statuses(statuses, receiver, followed_tag_ids)
    return statuses if statuses.empty?

    crutches = build_crutches(receiver.id, statuses)
    statuses.reject do |status|
      if status.tags.any? { |tag| followed_tag_ids.include?(tag.id) }
        filter_from_tags?(status, receiver.id, crutches)
      else
        filter_from_home(status, receiver.id, crutches, :home)
      end
    end
  end

  def push_to_antenna(antenna, status, update: false)
    return false unless antenna.account.user&.signed_in_recently?
    return false unless add_to_feed(:antenna, antenna.id, status, aggregate_reblogs: antenna.account.user&.aggregates_reblogs?)

    trim(:antenna, antenna.id)
    timeline = "timeline:antenna:#{antenna.id}"
    PushUpdateWorker.perform_async(antenna.account_id, status.id, timeline, { 'update' => update }) if push_update_required?(timeline)
    true
  end

  def unpush_from_antenna(antenna, status, update: false)
    return false unless remove_from_feed(:antenna, antenna.id, status, aggregate_reblogs: antenna.account.user&.aggregates_reblogs?)

    redis.publish("timeline:antenna:#{antenna.id}", { event: :delete, payload: status.id.to_s }.to_json) unless update
    true
  end

  def remove_status_from_antenna(antenna, target_status)
    timeline_key = key(:antenna, antenna.id)
    feed_status_ids = redis.zrange(timeline_key, 0, -1)
    status_ids = Status.where(id: feed_status_ids)
      .where(id: target_status.id)
      .or(Status.where(id: feed_status_ids, reblog_of_id: target_status.id))
      .pluck(:id)

    return if status_ids.empty?

    redis.zrem(timeline_key, status_ids)
    redis.zrem(key(:antenna, antenna.id, 'reblogs'), target_status.id)
    redis.del(key(:antenna, antenna.id, "reblogs:#{target_status.id}"))

    status_ids.each do |status_id|
      redis.publish("timeline:antenna:#{antenna.id}", { event: :delete, payload: status_id.to_s }.to_json)
    end
  end

  def clear_from_antennas(account, target_account)
    Antenna.where(account: account).find_each do |antenna|
      antenna_statuses_involving(antenna, target_account, include_mentions: true).each do |status|
        unpush_from_antenna(antenna, status)
      end
    end
  end

  def unmerge_blocker_from_antennas(blocker, into_account)
    Antenna.where(account: into_account).find_each do |antenna|
      antenna_statuses_involving(antenna, blocker, include_mentions: false).each do |status|
        unpush_from_antenna(antenna, status)
      end
    end
  end

  def unmerge_private_from_antennas(from_account, into_account)
    Antenna.where(account: into_account).find_each do |antenna|
      timeline_status_ids = redis.zrange(key(:antenna, antenna.id), 0, -1)

      from_account.statuses.where(visibility: :private).select(:id, :reblog_of_id).where(id: timeline_status_ids).reorder(nil).find_each do |status|
        unpush_from_antenna(antenna, status)
      end
    end
  end

  def push_update_required?(timeline_key)
    super || (Setting.misskey_compat_enabled && redis.exists?("subscribed:misskey:#{timeline_key}"))
  end

  private

  def antenna_statuses_involving(antenna, target_account, include_mentions:)
    timeline_status_ids = redis.zrange(key(:antenna, antenna.id), 0, -1)
    statuses            = Status.where(id: timeline_status_ids).select(:id, :reblog_of_id, :account_id).to_a
    reblogged_ids       = Status.where(id: statuses.filter_map(&:reblog_of_id), account: target_account).pluck(:id)
    with_mentions_ids   = include_mentions ? Mention.active.where(status_id: statuses.flat_map { |s| [s.id, s.reblog_of_id] }.compact, account: target_account).pluck(:status_id) : []

    statuses.select do |status|
      status.account_id == target_account.id || reblogged_ids.include?(status.reblog_of_id) || with_mentions_ids.include?(status.id) || with_mentions_ids.include?(status.reblog_of_id)
    end
  end

  def filter_from_list?(status, list)
    return false if Setting.misskey_compat_enabled && status.reply? && status.in_reply_to_account_id != status.account_id && ListAccount.exists?(list_id: list.id, account_id: status.account_id, with_replies: true)

    super
  end

  def filter_from_home(status, receiver_id, crutches, timeline_type = :home)
    result = super
    return result if result || !status.reblog?

    :filter if domain_muted_from_home?(status.reblog.account, crutches)
  end

  def filter_from_tags?(status, receiver_id, crutches)
    super || domain_muted_from_home?(status.account, crutches) || (status.reblog? && domain_muted_from_home?(status.reblog.account, crutches))
  end

  def filter_from_antenna?(status, receiver_id, crutches)
    return true if filter_from_tags?(status, receiver_id, crutches)
    return false unless status.reblog?
    return true if status.reblog.nil?

    reblog = status.reblog

    ([reblog.account_id] + (crutches[:active_mentions][reblog.id] || [])).any? { |target_account_id| crutches[:blocking][target_account_id] || crutches[:muting][target_account_id] } ||
      crutches[:blocked_by][reblog.account_id] ||
      crutches[:domain_blocking][reblog.account.domain] ||
      crutches[:hiding_reblogs][status.account_id] ||
      false
  end

  def build_crutches(receiver_id, statuses, list: nil)
    super.tap do |crutches|
      domains = statuses.flat_map { |status| [status.account.domain, status.reblog&.account&.domain] }.compact
      crutches[:domain_muting_home] = domains.empty? ? {} : AccountDomainMute.where(hide_from_home: true, account_id: receiver_id, domain: domains).pluck(:domain).index_with(true)
    end
  end

  def crutches_following(recipient_id, statuses, list)
    target_account_ids = statuses.flat_map { |status| [status.account_id, status.in_reply_to_account_id, status.reblog&.account_id] }.compact

    if list.blank? || list.show_followed?
      Follow.where(account_id: recipient_id, target_account_id: target_account_ids).pluck(:target_account_id).index_with(true)
    elsif list.show_list?
      ListAccount.where(list_id: list.id, account_id: target_account_ids).pluck(:account_id).index_with(true)
    else
      {}
    end
  end

  def domain_muted_from_home?(account, crutches)
    crutches[:domain_muting_home][account.domain] && !crutches[:following][account.id]
  end
end
