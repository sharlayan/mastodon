# frozen_string_literal: true

class InstanceMetadataUpdateWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'pull', retry: 3

  def perform(domain, priority: false)
    return if domain.blank?

    FetchInstanceThemeColorService.new.call(domain)
  rescue => e
    Rails.logger.error("Failed to update instance metadata for #{domain}: #{e.message}")
    raise if priority
  end
end
