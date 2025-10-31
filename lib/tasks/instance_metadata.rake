# frozen_string_literal: true

namespace :instance_metadata do
  desc 'Initialize metadata for existing remote instances'
  task initialize: :environment do
    domains = Account.remote.distinct.pluck(:domain).compact

    puts "Found #{domains.count} remote domains"

    domains.each_with_index do |domain, index|
      puts "[#{index + 1}/#{domains.count}] Processing #{domain}..."

      InstanceMetadata.find_or_create_by(domain: domain)
      InstanceMetadataUpdateWorker.perform_async(domain)

      sleep 0.1 # Rate limiting
    end

    puts 'Done!'
  end

  desc 'Refresh instance names for existing metadata'
  task refresh_names: :environment do
    domains = InstanceMetadata.where('instance_name IS NULL OR instance_name = ?', '').pluck(:domain)

    puts "Found #{domains.count} domains without instance names"

    domains.each_with_index do |domain, index|
      puts "[#{index + 1}/#{domains.count}] Updating #{domain}..."
      InstanceMetadataUpdateWorker.perform_async(domain)
      sleep 0.1
    end

    puts 'Done!'
  end

  desc 'Refresh outdated metadata'
  task refresh_outdated: :environment do
    Scheduler::InstanceMetadataRefreshScheduler.new.perform
  end
end
