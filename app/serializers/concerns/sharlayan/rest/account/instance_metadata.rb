# frozen_string_literal: true

module Sharlayan::REST::Account::InstanceMetadata
  extend ActiveSupport::Concern

  included do
    attribute :server_features, if: :instance_metadata_enabled?
    attribute :software, if: :instance_metadata_enabled?
  end

  def instance_metadata_enabled?
    Setting.instance_metadata_enabled
  end

  def server_features
    return ::InstanceMetadata.local_server_features if object.local?
    return ::InstanceMetadata.blank_server_features if object.domain.blank?

    ::InstanceMetadata.cached_by_domain(object.domain)&.server_features || ::InstanceMetadata.blank_server_features
  end

  def software
    return 'mastodon' if object.local?
    return nil if object.domain.blank?

    ::InstanceMetadata.cached_by_domain(object.domain)&.software
  end
end
