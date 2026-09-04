# frozen_string_literal: true

module Sharlayan::PostStatus
  class Preparation
    Result = Struct.new(:content_type, :mfm, :sensitive, :visibility, :limited_scope, :circle, :quoted_status, :implicit_quote, keyword_init: true)

    def initialize(account:, options:, text:, in_reply_to:, quoted_status:)
      @account = account
      @options = options
      @text = text
      @in_reply_to = in_reply_to
      @quoted_status = quoted_status
    end

    def call(media:, content_type:, sensitive:, visibility:)
      ActiveRecord::Associations::Preloader.new(records: media, associations: :drive_file).call
      content_type = 'text/plain' if content_type == 'text/x-mfm' && !Setting.mfm_enabled
      mfm = Setting.mfm_enabled && (content_type == 'text/x-mfm' || MfmDetector.contains_mfm?(@text))
      circle, visibility, limited_scope = prepare_circle(visibility)
      quoted_status, implicit_quote = prepare_quote

      Result.new(
        content_type: content_type,
        mfm: mfm,
        sensitive: sensitive || media.any? { |item| item.drive_file&.sensitive? },
        visibility: visibility,
        limited_scope: limited_scope,
        circle: circle,
        quoted_status: quoted_status,
        implicit_quote: implicit_quote
      )
    end

    private

    def prepare_circle(visibility)
      return [nil, visibility, nil] if @options[:circle_id].blank? && visibility&.to_sym != :circle

      raise ActiveRecord::RecordNotFound unless Setting.circles_enabled

      [@account.circles.find(@options[:circle_id]), :limited, :circle]
    end

    def prepare_quote
      implicit_quote = @options[:implicit_quote_from_url] == true
      return [@quoted_status, implicit_quote] if @quoted_status.present?
      return [nil, implicit_quote] unless auto_quote_from_url_enabled?

      quoted_status = Sharlayan::PostStatus::ImplicitQuote.new(account: @account, text: @text, in_reply_to: @in_reply_to).detect
      [quoted_status, quoted_status.present?]
    end

    def auto_quote_from_url_enabled?
      Setting.auto_quote_from_url && @account.user&.setting_auto_quote_from_url
    end
  end
end
