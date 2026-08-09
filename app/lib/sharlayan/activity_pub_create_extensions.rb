# frozen_string_literal: true

module Sharlayan::ActivityPubCreateExtensions
  extend ActiveSupport::Concern

  private

  def sharlayan_status_params(parser)
    {
      mfm: parser.mfm?,
      mfm_text: parser.mfm? ? parser.mfm_source_text : nil,
      limited_scope: parser.limited_scope,
    }
  end

  def sharlayan_quote_attributes(parser)
    { from_misskey: parser.from_misskey? }
  end

  def download_remote_media_with_budget!(media_attachment, download_budget)
    media_attachment.download_file!(size_limit: download_budget.size_limit(MediaAttachment::VIDEO_LIMIT))
    download_budget.consume(media_attachment.file_file_size)

    return unless download_budget.available?

    media_attachment.download_thumbnail!(size_limit: download_budget.size_limit(MediaAttachment::IMAGE_LIMIT))
    download_budget.consume(media_attachment.thumbnail_file_size)
  end

  def accepted_through_relay?
    requested_through_relay? && !DomainBlock.reject_relay?(@account.domain)
  end

  def relay_public_timeline_stream_suppressed?
    relay = relay_from_delivery
    relay&.enabled? && relay.suppress_public_timeline_stream?
  end

  def relay_from_delivery
    return unless @options[:relayed_through_actor].is_a?(Account)

    return @relay_from_delivery if defined?(@relay_from_delivery)

    @relay_from_delivery = Relay.find_by(inbox_url: @options[:relayed_through_actor].inbox_url)
  end
end
