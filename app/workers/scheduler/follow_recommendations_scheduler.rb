# frozen_string_literal: true

class Scheduler::FollowRecommendationsScheduler
  include Sidekiq::Worker

  sidekiq_options retry: 0, lock: :until_executed, lock_ttl: 1.day.to_i

  def perform
    return unless LowResourceFeatures.follow_recommendations_refresh_enabled?

    AccountSummary.refresh
    FollowRecommendation.refresh
  end
end
