# frozen_string_literal: true

module Sharlayan::Api::MuteTargetParams
  extend ActiveSupport::Concern

  MUTE_DOMAIN_RE = /\A[a-z0-9.-]+\z/

  private

  def require_scalar_mute_params!(*keys)
    return if keys.all? { |key| params[key].nil? || params[key].is_a?(String) || params[key].is_a?(Numeric) }

    render json: { error: 'Invalid parameter' }, status: 422
  end

  def normalized_mute_domain(value)
    domain = TagManager.instance.normalize_domain(value.to_s)
    domain if domain.present? && MUTE_DOMAIN_RE.match?(domain)
  rescue Addressable::URI::InvalidURIError
    nil
  end
end
