# frozen_string_literal: true

module Sharlayan::FeedManagerExtensions
  def filter(timeline_type, status, receiver)
    return super unless timeline_type == :antenna

    filter_from_tags?(status, receiver.account_id, build_crutches(receiver.account_id, [status])) ? :filter : nil
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

  def push_update_required?(timeline_key)
    super || (Setting.misskey_compat_enabled && redis.exists?("subscribed:misskey:#{timeline_key}"))
  end

  private

  def filter_from_home(status, receiver_id, crutches, timeline_type = :home)
    result = super
    return result if result || !status.reblog?

    :filter if domain_muted_from_home?(status.reblog.account, crutches)
  end

  def filter_from_tags?(status, receiver_id, crutches)
    super || domain_muted_from_home?(status.account, crutches) || (status.reblog? && domain_muted_from_home?(status.reblog.account, crutches))
  end

  def build_crutches(receiver_id, statuses, list: nil)
    super.tap do |crutches|
      domains = statuses.flat_map { |status| [status.account.domain, status.reblog&.account&.domain] }.compact
      crutches[:domain_muting_home] = AccountDomainMute.where(hide_from_home: true, account_id: receiver_id, domain: domains).pluck(:domain).index_with(true)
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
