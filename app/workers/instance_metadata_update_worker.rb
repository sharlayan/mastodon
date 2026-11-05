# frozen_string_literal: true

class InstanceMetadataUpdateWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'pull', retry: 3, lock: :until_executed, lock_ttl: 1.hour.to_i

  def perform(domain, priority: false)
    return if domain.blank?
    return unless Setting.instance_metadata_enabled

    FetchInstanceThemeColorService.new.call(domain)
  rescue => e
    Rails.logger.error("Failed to update instance metadata for #{domain}: #{e.message}")
    raise if priority
  end
end
