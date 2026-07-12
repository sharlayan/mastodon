# frozen_string_literal: true

class PostStatusService < BaseService
  include Redisable
  include Lockable
  include LanguagesHelper

  # How much to delay sending an e-mail about a new post, to allow grouping multiple posts
  EMAIL_DISTRIBUTION_DELAY = 5.minutes.freeze

  # If the job is not executed within this timeframe, it will lose its arguments
  EMAIL_DISTRIBUTION_TTL = 1.hour.to_i

  # How many URLs in the post body to probe when auto-detecting an implicit quote
  IMPLICIT_QUOTE_URL_SCAN_LIMIT = 3

  class UnexpectedMentionsError < StandardError
    attr_reader :accounts

    def initialize(message, accounts)
      super(message)
      @accounts = accounts
    end
  end

  # Post a text status update, fetch and notify remote users mentioned
  # @param [Account] account Account from which to post
  # @param [Hash] options
  # @option [String] :text Message
  # @option [Status] :thread Optional status to reply to
  # @option [Status] :quoted_status Optional status to quote
  # @option [String] :quote_approval_policy Approval policy for quotes, one of `public`, `followers` or `nobody`
  # @option [Boolean] :sensitive
  # @option [String] :visibility
  # @option [String] :spoiler_text
  # @option [String] :language
  # @option [String] :scheduled_at
  # @option [Hash] :poll Optional poll to attach
  # @option [Enumerable] :media_ids Optional array of media IDs to attach
  # @option [Doorkeeper::Application] :application
  # @option [String] :idempotency Optional idempotency key
  # @option [Boolean] :with_rate_limit
  # @option [Enumerable] :allowed_mentions Optional array of expected mentioned account IDs, raises `UnexpectedMentionsError` if unexpected accounts end up in mentions
  # @return [Status]
  def call(account, options = {})
    @account     = account
    @options     = options
    @text        = @options[:text] || ''
    @in_reply_to = @options[:thread]
    @quoted_status = @options[:quoted_status]

    with_idempotency do
      validate_media!
      preprocess_attributes!

      if scheduled?
        schedule_status!
      else
        process_status!
      end
    end

    unless scheduled?
      postprocess_status!
      bump_potential_friendship!
    end

    @status
  rescue Antispam::SilentlyDrop => e
    e.status
  end

  private

  def fill_blank_text!
    return unless @text.blank? && @options[:spoiler_text].present? && @quoted_status.blank?

    @text = begin
      if @media&.any?(&:video?) || @media&.any?(&:gifv?)
        '📹'
      elsif @media&.any?(&:audio?)
        '🎵'
      elsif @media&.any?(&:image?)
        '🖼'
      else
        '.'
      end
    end
  end

  def preprocess_attributes!
    fill_blank_text!
    @content_type = @options[:content_type] || @account.user&.setting_default_content_type
    # Strip MFM content type if server MFM is disabled
    @content_type = 'text/plain' if @content_type == 'text/x-mfm' && !Setting.mfm_enabled
    @mfm = Setting.mfm_enabled && (@content_type == 'text/x-mfm' || MfmDetector.contains_mfm?(@text))
    @sensitive    = (@options[:sensitive].nil? ? @account.user&.setting_default_sensitive : @options[:sensitive]) || @options[:spoiler_text].present?
    @visibility   = @options[:visibility] || @account.user&.setting_default_privacy
    load_circle! if @visibility&.to_sym == :circle
    @visibility = :unlisted if @visibility&.to_sym == :public && @account.silenced?
    detect_implicit_quote!
    @visibility   = :private if @quoted_status&.private_visibility? && %i(public unlisted).include?(@visibility&.to_sym)
    @scheduled_at = @options[:scheduled_at]&.to_datetime
    @scheduled_at = nil if scheduled_in_the_past?
  rescue ArgumentError
    raise ActiveRecord::RecordInvalid
  end

  def load_circle!
    raise ActiveRecord::RecordNotFound unless Setting.circles_enabled

    @circle        = @account.circles.find(@options[:circle_id])
    @visibility    = :limited
    @limited_scope = :circle
  end

  def process_status!
    @status = @account.statuses.new(status_attributes)
    process_mentions_service.call(@status, circle: @circle)
    @status.limited_scope = :personal if @circle.present? && @status.mentions.empty?
    safeguard_mentions!(@status)
    safeguard_private_mention_quote!(@status)
    attach_tagged_objects!(@status)
    attach_quote!(@status)

    antispam = Antispam.new(@status)
    antispam.local_preflight_check!

    # The following transaction block is needed to wrap the UPDATEs to
    # the media attachments when the status is created
    ApplicationRecord.transaction do
      @status.save!
      @circle.statuses << @status if @circle.present?
      attach_clips!(@status)
    end
  end

  def attach_clips!(status)
    return unless Setting.clips_enabled
    return if @options[:clip_ids].blank?

    @account.clips.where(id: @options[:clip_ids]).find_each do |clip|
      clip.statuses << status
    end
  end

  def safeguard_private_mention_quote!(status)
    return if @quoted_status.nil? || @visibility.to_sym != :direct

    # The mentions array test here is awkward because the relationship is not persisted at this time
    return if @quoted_status.account_id == @account.id || status.mentions.to_a.any? { |mention| mention.account_id == @quoted_status.account_id && !mention.silent }

    status.errors.add(:base, I18n.t('statuses.errors.quoted_user_not_mentioned'))
    raise ActiveRecord::RecordInvalid, status
  end

  def detect_implicit_quote!
    return if @quoted_status.present?
    return unless auto_quote_from_url_enabled?

    @quoted_status  = quotable_status_from_text
    @implicit_quote = @quoted_status.present?
  end

  def auto_quote_from_url_enabled?
    Setting.auto_quote_from_url && @account.user&.setting_auto_quote_from_url
  end

  def quotable_status_from_text
    @text.to_s.scan(FetchLinkCardService::URL_PATTERN).filter_map { |match| match[1] }.uniq.take(IMPLICIT_QUOTE_URL_SCAN_LIMIT).each do |url|
      status = resolve_status_from_url(url)
      return status if status.present? && quotable?(status)
    end

    nil
  end

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

  def attach_quote!(status)
    return if @quoted_status.nil?

    status.quote = Quote.create(quoted_status: @quoted_status, status: status, legacy: @implicit_quote || false)
    status.quote.ensure_quoted_access

    status.quote.accept! if accept_quote_without_request?
  end

  def accept_quote_without_request?
    return true if @implicit_quote

    if !@quoted_status.local? && @quoted_status.account.domain.present?
      instance_metadata = InstanceMetadata.for_domain(@quoted_status.account.domain)
      instance_metadata.present? && instance_metadata.misskey_based?
    elsif @quoted_status.local?
      StatusPolicy.new(@status.account, @quoted_status).quote?
    else
      false
    end
  end

  def attach_tagged_objects!(status)
    ProcessLinksService.new.call(status)
  end

  def safeguard_mentions!(status)
    return if @options[:allowed_mentions].nil?

    expected_account_ids = @options[:allowed_mentions].map(&:to_i)

    unexpected_accounts = status.mentions.map(&:account).to_a.reject { |mentioned_account| expected_account_ids.include?(mentioned_account.id) }
    return if unexpected_accounts.empty?

    raise UnexpectedMentionsError.new('Post would be sent to unexpected accounts', unexpected_accounts)
  end

  def schedule_status!
    status_for_validation = @account.statuses.build(status_attributes)
    safeguard_private_mention_quote!(status_for_validation)

    antispam = Antispam.new(status_for_validation)
    antispam.local_preflight_check!

    if status_for_validation.valid?
      # Marking the status as destroyed is necessary to prevent the status from being
      # persisted when the associated media attachments get updated when creating the
      # scheduled status.
      status_for_validation.destroy

      # The following transaction block is needed to wrap the UPDATEs to
      # the media attachments when the scheduled status is created

      ApplicationRecord.transaction do
        @status = @account.scheduled_statuses.create!(scheduled_status_attributes)
      end
    else
      raise ActiveRecord::RecordInvalid
    end
  rescue Antispam::SilentlyDrop
    @status = @account.scheduled_status.new(scheduled_status_attributes).tap(&:delete)
  end

  def postprocess_status!
    process_hashtags_service.call(@status)
    Trends.tags.register(@status)
    LinkCrawlWorker.perform_async(@status.id)
    DistributionWorker.perform_async(@status.id)
    process_email_subscriptions!
    ActivityPub::DistributionWorker.perform_async(@status.id) unless @status.local_only? || @status.limited_personal?
    PollExpirationNotifyWorker.perform_at(@status.poll.expires_at, @status.poll.id) if @status.poll
    ActivityPub::QuoteRequestWorker.perform_async(@status.quote.id) if @status.quote&.quoted_status.present? && !@status.quote&.quoted_status&.local? && !@status.quote.legacy?
  end

  def process_email_subscriptions!
    return unless Rails.application.config.x.email_subscriptions && Setting.email_subscriptions &&
                  @status.public_visibility? && (!@status.reply? || @status.in_reply_to_account_id == @status.account_id) &&
                  @status.account.user_can?(:manage_email_subscriptions) &&
                  @status.account.user_email_subscriptions_enabled?

    # To allow e-mail grouping, pass the arguments via a redis set and schedule
    # a unique worker a few minutes in the future, in case the user makes subsequent
    # posts within that time window
    redis.sadd("email_subscriptions:#{@status.account_id}:next_batch", @status.id)
    redis.expire("email_subscriptions:#{@status.account_id}:next_batch", EMAIL_DISTRIBUTION_TTL)
    EmailDistributionWorker.perform_in(EMAIL_DISTRIBUTION_DELAY, @status.account_id)
  end

  def validate_media!
    if @options[:media_ids].blank? || !@options[:media_ids].is_a?(Enumerable)
      @media = []
      return
    end

    raise Mastodon::ValidationError, I18n.t('media_attachments.validations.too_many') if @options[:media_ids].size > Status::MEDIA_ATTACHMENTS_LIMIT

    @media = @account.media_attachments.where(status_id: nil).where(id: @options[:media_ids].take(Status::MEDIA_ATTACHMENTS_LIMIT).map(&:to_i))

    not_found_ids = @options[:media_ids].map(&:to_i) - @media.map(&:id)
    raise Mastodon::ValidationError, I18n.t('media_attachments.validations.not_found', ids: not_found_ids.join(', ')) if not_found_ids.any?

    raise Mastodon::ValidationError, I18n.t('media_attachments.validations.images_and_video') if @media.size > 1 && @media.find(&:audio_or_video?)
    raise Mastodon::ValidationError, I18n.t('media_attachments.validations.not_ready') if @media.any?(&:not_processed?)
  end

  def process_mentions_service
    ProcessMentionsService.new
  end

  def process_hashtags_service
    ProcessHashtagsService.new
  end

  def scheduled?
    @scheduled_at.present?
  end

  def idempotency_key
    "idempotency:status:#{@account.id}:#{@options[:idempotency]}"
  end

  def idempotency_given?
    @options[:idempotency].present?
  end

  def idempotency_duplicate
    if scheduled?
      @account.scheduled_statuses.find(@idempotency_duplicate)
    else
      @account.statuses.find(@idempotency_duplicate)
    end
  end

  def idempotency_duplicate?
    @idempotency_duplicate = redis.get(idempotency_key)
  end

  def with_idempotency
    return yield unless idempotency_given?

    with_redis_lock("idempotency:lock:status:#{@account.id}:#{@options[:idempotency]}") do
      return idempotency_duplicate if idempotency_duplicate?

      yield

      redis.setex(idempotency_key, 3_600, @status.id)
    end
  end

  def scheduled_in_the_past?
    @scheduled_at.present? && @scheduled_at <= Time.now.utc
  end

  def bump_potential_friendship!
    return if !@status.reply? || @account.id == @status.in_reply_to_account_id

    ActivityTracker.increment('activity:interactions')
  end

  def status_attributes
    {
      text: @text,
      media_attachments: @media || [],
      ordered_media_attachment_ids: (@options[:media_ids] || []).map(&:to_i) & @media.map(&:id),
      thread: @in_reply_to,
      poll_attributes: poll_attributes,
      sensitive: @sensitive,
      spoiler_text: @options[:spoiler_text] || '',
      visibility: @visibility,
      limited_scope: @limited_scope,
      language: valid_locale_cascade(@options[:language], @account.user&.preferred_posting_language, I18n.default_locale),
      application: @options[:application],
      content_type: @content_type,
      mfm: @mfm,
      mfm_text: (@mfm ? @text : nil),
      local_only: @options[:local_only],
      rate_limit: @options[:with_rate_limit],
      quote_approval_policy: @options[:quote_approval_policy],
    }.compact
  end

  def scheduled_status_attributes
    {
      scheduled_at: @scheduled_at,
      media_attachments: @media || [],
      params: scheduled_options,
    }
  end

  def poll_attributes
    return if @options[:poll].blank?

    @options[:poll].merge(account: @account, voters_count: 0)
  end

  def scheduled_options
    @options.dup.tap do |options_hash|
      options_hash[:in_reply_to_id]  = options_hash.delete(:thread)&.id
      options_hash[:application_id]  = options_hash.delete(:application)&.id
      options_hash[:quoted_status_id] = options_hash.delete(:quoted_status)&.id
      options_hash[:scheduled_at]    = nil
      options_hash[:idempotency]     = nil
      options_hash[:with_rate_limit] = false
    end
  end
end
