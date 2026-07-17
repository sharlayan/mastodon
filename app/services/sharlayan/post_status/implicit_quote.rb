# frozen_string_literal: true

module Sharlayan::PostStatus
  class ImplicitQuote
    URL_SCAN_LIMIT = 3

    def initialize(account:, text:, in_reply_to:)
      @account = account
      @text = text
      @in_reply_to = in_reply_to
    end

    def detect
      urls = @text.to_s.scan(FetchLinkCardService::URL_PATTERN).filter_map { |match| match[1] }.uniq.take(URL_SCAN_LIMIT)
      return if urls.empty?

      RateLimiter.new(@account, family: :implicit_quotes).record!

      urls.each do |url|
        status = resolve_status_from_url(url)
        return status if status.present? && quotable?(status)
      end

      nil
    end

    private

    def resolve_status_from_url(url)
      resource = ResolveURLService.new.call(url, on_behalf_of: @account)
      resource.is_a?(Status) ? resource : nil
    rescue => e
      Rails.logger.debug { "Error resolving implicit quote URL #{url}: #{e}" }
      nil
    end

    def quotable?(status)
      return false if status.id == @in_reply_to&.id
      return false unless StatusPolicy.new(@account, status).show?

      status.account_id == @account.id || status.distributable?
    end
  end
end
