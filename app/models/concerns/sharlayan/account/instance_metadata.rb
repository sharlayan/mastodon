# frozen_string_literal: true

module Sharlayan::Account::InstanceMetadata
  extend ActiveSupport::Concern

  included do
    after_commit :schedule_instance_metadata_update, on: [:create, :update], if: :should_update_instance_metadata?
  end

  private

  def should_update_instance_metadata?
    return false if domain.blank?

    metadata = ::InstanceMetadata.find_by(domain: domain)
    metadata.nil? || metadata.theme_color_needs_update?
  end

  def schedule_instance_metadata_update
    InstanceMetadataUpdateWorker.perform_async(domain)
  end
end
