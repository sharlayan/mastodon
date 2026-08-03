# frozen_string_literal: true

class Scheduler::FederationRequestStatisticsCleanupScheduler
  include Sidekiq::Worker

  sidekiq_options retry: 0, lock: :until_executed, lock_ttl: 1.day.to_i

  def perform
    FederationRequestStatistic.expired.in_batches.delete_all
  end
end
