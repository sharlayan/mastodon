# frozen_string_literal: true

class Api::MisskeyCompat::FetchController < Api::MisskeyCompat::BaseController
  RSS_CACHE_TTL = 3.minutes
  RSS_SIZE_LIMIT = 2.megabytes
  EXTERNAL_RESOURCE_SIZE_LIMIT = 256.kilobytes
  INTERNAL_ERROR_ID = '5d37dbcb-891e-41ca-a3d6-e690c97775ac'
  FETCH_ERRORS = [
    Mastodon::UnexpectedResponseError, Mastodon::HostValidationError, Mastodon::LengthValidationError,
    Addressable::URI::InvalidURIError, *Mastodon::HTTP_CONNECTION_ERRORS
  ].freeze

  requires_misskey_permission 'read:account', :rss, :external_resources

  before_action :require_user_if_authenticated!, only: :rss
  before_action :require_user!, only: :external_resources
  before_action :require_native_user_token!, only: :external_resources
  before_action :require_fetch_url!

  def rss
    url = params[:url].to_s
    cache_key = "misskey_compat:fetch_rss:#{Digest::SHA256.hexdigest(url)}"
    feed = Rails.cache.read(cache_key)

    if feed.nil?
      return if rate_limited?(:misskey_compat_fetch_rss)

      feed = MisskeyCompat::RSSParser.parse(fetch_body(url, accept: 'application/rss+xml, */*', limit: RSS_SIZE_LIMIT))
      Rails.cache.write(cache_key, feed, expires_in: RSS_CACHE_TTL)
    end

    expires_in RSS_CACHE_TTL, public: true if request.get? && current_user.nil?
    render json: feed
  rescue MisskeyCompat::RSSParser::UnrecognizedFeedError, *FETCH_ERRORS
    render_internal_error
  end

  def external_resources
    return render_invalid_param('#/properties/hash', 'is required') unless params.key?(:hash)
    return render_invalid_param('#/properties/hash/type', 'must be string') unless params[:hash].is_a?(String)
    return if rate_limited?(:misskey_compat_external_resources)

    resource = JSON.parse(fetch_body(params[:url].to_s, accept: 'application/json, */*', limit: EXTERNAL_RESOURCE_SIZE_LIMIT))
    return render_error('External resource returned invalid schema.', 'EXT_RESOURCE_RETURNED_INVALID_SCHEMA', 400, id: 'bb774091-7a15-4a70-9dc5-6ac8cf125856') unless valid_resource?(resource) # rubocop:disable I18n/RailsI18n/DecorateString
    return render_error('Hash did not match.', 'EXT_RESOURCE_HASH_DIDNT_MATCH', 400, id: '693ba8ba-b486-40df-a174-72f8279b56a4') unless Digest::SHA512.hexdigest(resource['data'].gsub("\r\n", "\n")) == params[:hash] # rubocop:disable I18n/RailsI18n/DecorateString

    render json: { type: resource['type'], data: resource['data'] }
  rescue JSON::ParserError, *FETCH_ERRORS
    render_internal_error
  end

  private

  def require_fetch_url!
    return render_invalid_param('#/properties/url', 'is required') unless params.key?(:url)
    return render_invalid_param('#/properties/url/type', 'must be string') unless params[:url].is_a?(String)

    render_invalid_param('#/properties/url', 'must be an HTTP(S) URL') unless http_url?(params[:url])
  end

  def http_url?(url)
    parsed = Addressable::URI.parse(url)
    %w(http https).include?(parsed.scheme) && parsed.host.present? && parsed.userinfo.nil?
  rescue Addressable::URI::InvalidURIError
    false
  end

  def fetch_body(url, accept:, limit:)
    Request.new(:get, url).add_headers('Accept' => accept).perform do |response|
      raise Mastodon::UnexpectedResponseError, response unless response.code.between?(200, 299)

      response.body_with_limit(limit)
    end
  end

  def valid_resource?(resource)
    resource.is_a?(Hash) && resource['type'].is_a?(String) && resource['data'].is_a?(String) && resource['type'].present? && resource['data'].present?
  end

  def render_internal_error
    render_error('Internal error occurred. Please contact us if the error persists.', 'INTERNAL_ERROR', 500, id: INTERNAL_ERROR_ID, kind: 'server') # rubocop:disable I18n/RailsI18n/DecorateString
  end
end
