# frozen_string_literal: true

class Scheduler::FederationRequestStatisticsScheduler
  include Sidekiq::Worker

  sidekiq_options retry: 0, lock: :until_executed, lock_ttl: 5.minutes.to_i

  def perform
    Sharlayan::FederationRequestTracker.flush!
  end
end
