# frozen_string_literal: true

class Sharlayan::HomeFeedBoundary
  include Redisable

  CANDIDATE_LIMIT = 20

  def self.resolve(account, status_id)
    new(account, status_id).resolve
  end

  def initialize(account, status_id)
    @account   = account
    @status_id = status_id.to_i
  end

  def resolve
    return nil unless @status_id.positive?

    candidates = feed_reblogs
    return nil if candidates.empty?

    FeedManager.instance.filter_home_statuses(candidates, @account, followed_tag_ids).first&.id
  end

  private

  def feed_reblogs
    reblogs = Status.where(reblog_of_id: @status_id)

    reblogs
      .where(account_id: @account.following.select(:id))
      .or(reblogs.where(account_id: @account.id))
      .includes(:tags, :account, reblog: :account)
      .reorder(id: :asc)
      .limit(CANDIDATE_LIMIT)
      .to_a
      .reject { |reblog| hidden_own_reblog?(reblog) }
  end

  def hidden_own_reblog?(reblog)
    reblog.account_id == @account.id &&
      !@account.user&.setting_display_own_boosts &&
      redis.zscore(FeedManager.instance.key(:home, @account.id), reblog.id).nil?
  end

  def followed_tag_ids
    TagFollow.where(account: @account).pluck(:tag_id).to_set
  end
end
