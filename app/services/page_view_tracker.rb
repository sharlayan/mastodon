# frozen_string_literal: true

class PageViewTracker
  AUTHENTICATED_DEDUPLICATION_TTL = 10.minutes
  ANONYMOUS_DEDUPLICATION_TTL = 30.minutes

  def initialize(page, account:, request:)
    @page = page
    @account = account
    @request = request
  end

  def call
    return false if page.account_id == account&.id || crawler? || !acquire_deduplication_key

    page.increment!(counter_column)
    true
  rescue Redis::BaseError
    false
  end

  private

  attr_reader :page, :account, :request

  def counter_column
    account ? :authenticated_views_count : :anonymous_views_count
  end

  def acquire_deduplication_key
    RedisConnection.with do |redis|
      redis.set(deduplication_key, 1, nx: true, ex: deduplication_ttl)
    end
  end

  def deduplication_key
    identity = account ? "account:#{account.id}" : "visitor:#{anonymous_identity}"
    "page_view:v1:#{page.id}:#{identity}"
  end

  def deduplication_ttl
    account ? AUTHENTICATED_DEDUPLICATION_TTL : ANONYMOUS_DEDUPLICATION_TTL
  end

  def anonymous_identity
    OpenSSL::HMAC.hexdigest('SHA256', Rails.application.secret_key_base, "#{normalized_remote_ip}\0#{request.user_agent}")
  end

  def normalized_remote_ip
    address = IPAddr.new(request.remote_ip)
    return address.to_s if address.ipv4?

    IPAddr.new(address.to_i & (((2**128) - 1) ^ ((2**64) - 1)), Socket::AF_INET6).to_s
  rescue IPAddr::InvalidAddressError
    request.remote_ip.to_s
  end

  def crawler?
    request.user_agent.present? && Browser.new(request.user_agent).bot?
  end
end
