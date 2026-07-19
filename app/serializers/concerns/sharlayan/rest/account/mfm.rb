# frozen_string_literal: true

module Sharlayan::REST::Account::Mfm
  extend ActiveSupport::Concern

  included do
    attribute :mfm, if: :mfm?
  end

  def mfm
    true
  end

  def mfm?
    return false if object.unavailable?
    return false unless object.mfm?

    object.local? || instance_supports_mfm?
  end

  def instance_supports_mfm?
    return false unless Setting.instance_metadata_enabled
    return false if object.domain.blank?

    InstanceMetadata.cached_by_domain(object.domain)&.misskey_based? || false
  end
end
