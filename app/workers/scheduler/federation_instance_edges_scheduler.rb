# frozen_string_literal: true

class Scheduler::FederationInstanceEdgesScheduler
  include Sidekiq::Worker

  sidekiq_options retry: 0, lock: :until_executed, lock_ttl: 1.day.to_i

  def perform
    Sharlayan::FederationEdgeAggregator.call
  end
end
