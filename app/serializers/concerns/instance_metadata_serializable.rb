# frozen_string_literal: true

module InstanceMetadataSerializable
  extend ActiveSupport::Concern

  included do
    attribute :instance_metadata, if: :include_instance_metadata?
  end

  def instance_metadata
    return nil if metadata_domain.blank?

    begin
      metadata = fetch_or_create_metadata(metadata_domain)
      return nil if metadata.nil?

      schedule_metadata_update(metadata_domain) if should_update_metadata?(metadata)

      serialize_metadata(metadata)
    rescue => e
      Rails.logger.error("Failed to fetch instance_metadata for domain #{metadata_domain}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      nil
    end
  end

  def include_instance_metadata?
    Setting.instance_metadata_enabled && metadata_domain.present?
  end

  private

  def metadata_domain
    raise NotImplementedError, 'Subclass must implement metadata_domain'
  end

  def fetch_or_create_metadata(domain)
    InstanceMetadata.cached_find_or_create_by_domain(domain)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
    Rails.logger.warn("Could not create InstanceMetadata for #{domain}: #{e.message}")
    nil
  end

  def should_update_metadata?(metadata)
    return false if metadata.nil?
    return true if metadata.software.blank?
    return true if metadata.instance_name.blank?
    return true if metadata.metadata_needs_update?

    false
  end

  def schedule_metadata_update(domain)
    InstanceMetadataUpdateWorker.perform_async(domain)
  rescue => e
    Rails.logger.warn("Could not schedule metadata update for #{domain}: #{e.message}")
  end

  def serialize_metadata(metadata)
    return nil if metadata.nil?

    {
      domain: metadata.domain,
      instance_name: metadata.instance_name_with_fallback,
      software: metadata.software,
      version: metadata.version,
      theme_color: metadata.theme_color_with_fallback,
      favicon_url: metadata.favicon_url_with_fallback,
      server_features: metadata.server_features,
    }
  rescue => e
    Rails.logger.error("Failed to serialize metadata for #{metadata.domain}: #{e.message}")
    nil
  end
end
