# frozen_string_literal: true

module Sharlayan
  class PostStatusPipeline
    attr_reader :options, :quoted_status

    def initialize(account:, options:, text:, in_reply_to:, quoted_status:)
      @account = account
      @options = options
      @text = text
      @in_reply_to = in_reply_to
      @quoted_status = quoted_status
    end

    def prepare!(media:, content_type:, sensitive:, visibility:)
      @prepared = Sharlayan::PostStatus::Preparation.new(
        account: @account,
        options: @options,
        text: @text,
        in_reply_to: @in_reply_to,
        quoted_status: @quoted_status
      ).call(media: media, content_type: content_type, sensitive: sensitive, visibility: visibility)
      @quoted_status = @prepared.quoted_status
      @options = @options.dup
      @options[:quoted_status] = @quoted_status
      @options[:implicit_quote_from_url] = true if @prepared.implicit_quote
      @options[:sensitive] = @prepared.sensitive
      @persistence = Sharlayan::PostStatus::Persistence.new(account: @account, options: @options, circle: @prepared.circle)
      self
    end

    def sensitive?
      @prepared.sensitive
    end

    def visibility
      @prepared.visibility
    end

    def prepare_status!(status, service)
      @persistence.process_mentions!(status, service, attributes: status_attributes)
      yield
      attach_quote!(status)
    end

    def persist_status!(status, media:, &block)
      @persistence.persist_status!(status, media: media, &block)
    end

    def persist_scheduled!(media:, &block)
      @persistence.persist_scheduled!(media: media, &block)
    end

    def attach_quote!(status)
      Sharlayan::PostStatus::Quote.new(quoted_status: @quoted_status, implicit_quote: @prepared.implicit_quote).attach!(status)
    end

    def status_attributes
      {
        limited_scope: @prepared.limited_scope,
        content_type: @prepared.content_type,
        mfm: @prepared.mfm,
        mfm_text: (@prepared.mfm ? @text : nil),
      }.compact
    end

    def after_commit!(status)
      ActivityPub::DistributionWorker.perform_async(status.id) unless status.local_only? || status.limited_personal?
      yield
      ActivityPub::QuoteRequestWorker.perform_async(status.quote.id) if status.quote&.quoted_status.present? && !status.quote.quoted_status.local? && !status.quote.legacy?
    end
  end
end
