# frozen_string_literal: true

module MisskeyCompat::SigninOriginPolicy
  module_function

  def allowed?(origin, base_url, configured_origins)
    normalized_origin = normalize(origin)
    return false if normalized_origin.nil?

    normalized_origin == normalize(base_url) || origins(configured_origins).include?(normalized_origin)
  end

  def origins(value)
    entries(value).filter_map { |entry| normalize(entry, https_only: true) }.uniq
  end

  def invalid_entries(value)
    entries(value).reject { |entry| normalize(entry, https_only: true) }
  end

  def normalize(value, https_only: false)
    uri = Addressable::URI.parse(value.to_s)
    return if uri.host.blank? || uri.user.present? || uri.password.present?
    return unless https_only ? uri.scheme == 'https' : %w(http https).include?(uri.scheme)
    return if uri.path.present? && uri.path != '/'
    return if uri.query.present? || uri.fragment.present?

    uri.path = nil
    uri.origin
  rescue Addressable::URI::InvalidURIError
    nil
  end

  def entries(value)
    value.to_s.split(/[\s,]+/).compact_blank
  end
end
