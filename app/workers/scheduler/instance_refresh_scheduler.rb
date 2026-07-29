# frozen_string_literal: true

class Scheduler::InstanceRefreshScheduler
  include Sidekiq::Worker

  sidekiq_options retry: 0, lock: :until_executed, lock_ttl: 1.day.to_i

  def perform
    return unless LowResourceFeatures.instance_refresh_enabled?

    Instance.refresh
    InstancesIndex.sync if Chewy.enabled?
  end
end
