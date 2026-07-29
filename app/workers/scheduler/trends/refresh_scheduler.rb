# frozen_string_literal: true

class Scheduler::Trends::RefreshScheduler
  include Sidekiq::Worker

  sidekiq_options retry: 0, lock: :until_executed, lock_ttl: 30.minutes.to_i

  def perform
    return unless LowResourceFeatures.trends_processing_enabled?

    Trends.refresh!
  end
end
