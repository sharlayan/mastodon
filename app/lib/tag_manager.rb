# frozen_string_literal: true

class TagManager
  include Singleton
  include RoutingHelper

  def web_domain?(domain)
    domain.nil? || domain.delete_suffix('/').casecmp(Rails.configuration.x.web_domain).zero?
  end

  def local_domain?(domain)
    domain.nil? || domain.delete_suffix('/').casecmp(Rails.configuration.x.local_domain).zero?
  end

  def normalize_domain(domain)
    return if domain.nil?

    host, port = domain.strip.delete_suffix('/').match(/\A(.*?)(?::(\d+))?\z/).captures
    normalized_host = Addressable::URI.new.tap do |uri|
      uri.host = host
    end.normalized_host

    port ? "#{normalized_host}:#{port}" : normalized_host
  end

  def local_url?(url)
    uri    = Addressable::URI.parse(url).normalize
    return false unless uri.host

    domain = uri.host + (uri.port ? ":#{uri.port}" : '')

    TagManager.instance.web_domain?(domain)
  rescue Addressable::URI::InvalidURIError, IDN::Idna::IdnaError
    false
  end
end
