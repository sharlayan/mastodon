# frozen_string_literal: true

module Sharlayan::PostStatus
  class Quote
    def initialize(quoted_status:, implicit_quote:)
      @quoted_status = quoted_status
      @implicit_quote = implicit_quote
    end

    def attach!(status)
      return if @quoted_status.nil?

      status.quote = ::Quote.create(quoted_status: @quoted_status, status: status, legacy: @implicit_quote || false)
      status.quote.ensure_quoted_access
      status.quote.accept! if accept_without_request?(status)
    end

    private

    def accept_without_request?(status)
      return true if @implicit_quote

      if !@quoted_status.local? && @quoted_status.account.domain.present?
        metadata = InstanceMetadata.for_domain(@quoted_status.account.domain)
        metadata.present? && metadata.misskey_based?
      elsif @quoted_status.local?
        StatusPolicy.new(status.account, @quoted_status).quote?
      else
        false
      end
    end
  end
end
