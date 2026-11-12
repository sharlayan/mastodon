# frozen_string_literal: true

module Sharlayan::LinkPreviewDirectHosts
  HOST_PATTERN = /\A(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z](?:[a-z0-9-]{0,61}[a-z0-9])?\z/
  HIDDEN_SUFFIXES = %w(.onion .i2p).freeze

  module_function

  def allowed?(url, value = Setting.link_preview_direct_hosts)
    host = host_of(url)
    return false if host.nil?

    hosts(value).any? { |entry| host == entry || host.end_with?(".#{entry}") }
  end

  def hosts(value)
    entries(value).filter_map { |entry| normalize(entry) }.uniq
  end

  def invalid_entries(value)
    entries(value).reject { |entry| normalize(entry) }
  end

  def normalize(entry)
    host = Addressable::IDNA.to_ascii(entry.to_s.strip.downcase.delete_prefix('*.').delete_suffix('.'))
    host if HOST_PATTERN.match?(host) && HIDDEN_SUFFIXES.none? { |suffix| host.end_with?(suffix) }
  rescue Addressable::IDNA::PunycodeBigOutput, ArgumentError
    nil
  end

  def entries(value)
    value.to_s.split(/[\s,]+/).compact_blank
  end

  def host_of(url)
    uri = url.is_a?(Addressable::URI) ? url : Addressable::URI.parse(url.to_s)
    return unless %w(http https).include?(uri.scheme) && uri.user.nil? && uri.password.nil?

    uri.normalized_host&.delete_suffix('.')
  rescue Addressable::URI::InvalidURIError
    nil
  end
end
