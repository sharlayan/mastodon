# frozen_string_literal: true

module Sharlayan::REST::Status::InstanceMetadata
  extend ActiveSupport::Concern

  included do
    attribute :instance_metadata, if: :show_instance_info?
  end

  def instance_metadata
    return nil if object.account.domain.blank?

    begin
      metadata = ::InstanceMetadata.cached_by_domain(object.account.domain)

      if metadata.nil?
        InstanceMetadataUpdateWorker.perform_async(object.account.domain)
        return default_metadata(object.account.domain)
      end

      InstanceMetadataUpdateWorker.perform_async(object.account.domain) if metadata.metadata_needs_update?

      {
        domain: metadata.domain,
        instance_name: metadata.instance_name_with_fallback,
        software: metadata.software,
        version: metadata.version,
        theme_color: metadata.theme_color_with_fallback,
        favicon_url: metadata.favicon_url_with_fallback,
      }
    rescue => e
      Rails.logger.error("Failed to fetch instance_metadata for domain #{object.account.domain}: #{e.message}")
      nil
    end
  end

  def show_instance_info?
    Setting.instance_metadata_enabled && object.account.domain.present?
  end

  private

  def metadata_domain
    object.account.domain
  end
end
