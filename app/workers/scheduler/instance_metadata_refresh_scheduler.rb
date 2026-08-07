# frozen_string_literal: true

class Scheduler::InstanceMetadataRefreshScheduler
  include Sidekiq::Worker
  include DatabaseHelper

  sidekiq_options retry: 0

  def perform
    return unless Setting.instance_metadata_enabled

    missing_info_domains = InstanceMetadata.where('software IS NULL OR software = ? OR instance_name IS NULL OR instance_name = ? OR local_posts_count IS NULL', '', '').limit(50).pluck(:domain)

    missing_info_domains.each do |domain|
      InstanceMetadataUpdateWorker.perform_async(domain)
    end

    outdated_domains = InstanceMetadata.where.not(software: [nil, '']).where.not(instance_name: [nil, '']).where.not(local_posts_count: nil).where('theme_color_updated_at IS NULL OR theme_color_updated_at < ?', 7.days.ago).limit(50).pluck(:domain)

    outdated_domains.each do |domain|
      InstanceMetadataUpdateWorker.perform_async(domain)
    end

    active_domains = Account.remote.where.not(domain: nil).joins(:account_stat).where(account_stats: { last_status_at: 30.days.ago.. }).distinct.limit(30).pluck(:domain)

    active_domains.each do |domain|
      next if InstanceMetadata.exists?(domain: domain)

      InstanceMetadataUpdateWorker.perform_async(domain)
    end
  end
end
