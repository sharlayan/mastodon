# frozen_string_literal: true

class HideStatusService < BaseService
  include Redisable

  # Soft-hide a status: the row and its media survive, but the status leaves
  # every feed, index and public read path. Only the owner can read it back.
  # @param   [Status] status
  # @param   [Hash] options
  # @option  [Integer] :hidden_by_account_id
  def call(status, **options)
    raise Mastodon::NotPermittedError unless Sharlayan::SoftHide.enabled?

    @status  = status
    @account = status.account
    @options = options
    @payload = { event: :delete, payload: status.id.to_s }.to_json

    ApplicationRecord.transaction do
      hidden_status = RpHiddenStatus.create_or_find_by!(status: @status) do |record|
        record.hidden_by_account_id = @options[:hidden_by_account_id]
      end

      StatusPin.find_by(status: @status)&.destroy
      remove_user_references
      decrement_counter_caches if hidden_status.previously_new_record?
    end

    hide_reblogs

    remove_from_self if @account.local?
    remove_from_followers
    remove_from_lists
    remove_from_antennas
    remove_from_mentions
    remove_from_hashtags
    remove_from_public
    remove_from_media if @status.with_media?
    remove_from_direct if @status.direct_visibility?
    remove_from_admin

    deindex

    HideStatusMediaWorker.perform_async(@status.id) if @status.with_media?
  end

  private

  def decrement_counter_caches
    return if @status.direct_visibility?

    @account&.decrement_count!(:statuses_count)
    Status.with_rp_hidden.find_by(id: @status.reblog_of_id)&.decrement_count!(:reblogs_count) if @status.reblog?
    @status.thread&.decrement_count!(:replies_count) if @status.in_reply_to_id.present? && @status.distributable?
  end

  def remove_user_references
    @status.favourites.destroy_all
    @status.status_reactions.destroy_all
    @status.bookmarks.destroy_all
    @status.clip_statuses.destroy_all
    @status.notification&.destroy if @status.reblog?
  end

  def hide_reblogs
    return if @status.reblog?

    Status.unscoped.where(reblog_of_id: @status.id).find_each do |reblog|
      HideStatusService.new.call(reblog, **@options)
    end
  end

  def remove_from_self
    FeedManager.instance.unpush_from_home(@account, @status)
    FeedManager.instance.unpush_from_direct(@account, @status) if @status.direct_visibility?
  end

  def remove_from_followers
    @account.followers_for_local_distribution.includes(:user).reorder(nil).find_each do |follower|
      FeedManager.instance.unpush_from_home(follower, @status)
    end
  end

  def remove_from_lists
    @account.lists_for_local_distribution.select(:id, :account_id).includes(account: :user).reorder(nil).find_each do |list|
      FeedManager.instance.unpush_from_list(list, @status)
    end
  end

  def remove_from_antennas
    Antenna.matching(@status).each do |antenna|
      FeedManager.instance.unpush_from_antenna(antenna, @status)
    end
  end

  def remove_from_mentions
    @status.active_mentions.find_each do |mention|
      redis.publish("timeline:#{mention.account_id}", @payload)
    end
  end

  def remove_from_hashtags
    return unless @status.public_visibility?

    @status.tags.map(&:name).each do |hashtag|
      redis.publish("timeline:hashtag:#{hashtag.downcase}", @payload)
      redis.publish("timeline:hashtag:#{hashtag.downcase}:local", @payload) if @status.local?
    end
  end

  def remove_from_public
    return unless @status.public_visibility?

    redis.publish('timeline:public', @payload)
    redis.publish(@status.local? ? 'timeline:public:local' : 'timeline:public:remote', @payload)
  end

  def remove_from_media
    return unless @status.public_visibility?

    redis.publish('timeline:public:media', @payload)
    redis.publish(@status.local? ? 'timeline:public:local:media' : 'timeline:public:remote:media', @payload)
  end

  def remove_from_direct
    @status.active_mentions.each do |mention|
      FeedManager.instance.unpush_from_direct(mention.account, @status) if mention.account.local?
    end
  end

  def remove_from_admin
    return unless Sharlayan::AdminTimeline.enabled? && @account.local?

    redis.publish(Sharlayan::AdminTimeline::REDIS_CHANNEL, @payload)
  end

  def deindex
    return unless Chewy.enabled?

    Chewy.strategy.current.update(StatusesIndex, [@status])
    Chewy.strategy.current.update(PublicStatusesIndex, [@status])
  end
end
