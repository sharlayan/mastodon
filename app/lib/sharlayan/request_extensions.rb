# frozen_string_literal: true

module Sharlayan::RequestExtensions
  class DirectRedirectRefused < StandardError; end

  def initialize(verb, url, **options)
    @route = options.delete(:route)
    @proxied_options = options.dup
    super
    restrict_direct_redirects! if direct_route?
  end

  def perform(&block)
    super
  rescue DirectRedirectRefused
    Request.new(@verb, @url.to_s, **@proxied_options).add_headers(@headers.except('Date')).perform(&block)
  end

  private

  def proxy_url
    return {} if direct_route?

    super
  end

  def direct_route?
    return @direct_route if defined?(@direct_route)

    @direct_route = @route == :link_preview && Rails.configuration.x.http_client_proxy.present? && !hidden_service? && Sharlayan::LinkPreviewDirectHosts.allowed?(@url)
  end

  def restrict_direct_redirects!
    follow = @options[:follow]
    return unless follow.is_a?(Hash)

    @options[:follow] = follow.merge(
      on_redirect: lambda do |_response, request|
        raise DirectRedirectRefused unless Sharlayan::LinkPreviewDirectHosts.allowed?(request.uri)
      end
    )
  end
end
