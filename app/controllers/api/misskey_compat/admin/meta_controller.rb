# frozen_string_literal: true

class Api::MisskeyCompat::Admin::MetaController < Api::MisskeyCompat::MetaController
  include Api::MisskeyCompat::Admin::ServerAccess
  include DomainControlHelper

  STRING_SETTINGS = {
    name: :site_title,
    description: :site_short_description,
    maintainerName: :site_contact_username,
    maintainerEmail: :site_contact_email,
    themeColor: :theme_color,
  }.freeze

  misskey_admin_endpoint :admin_show, kind: 'read:admin:meta', role: :admin, permission: :manage_settings
  misskey_admin_endpoint :admin_update, kind: 'write:admin:meta', role: :admin, permission: :manage_settings

  def admin_show
    authorize :settings, :show?

    render json: detailed_meta.merge(admin_meta)
  end

  def admin_update
    authorize :settings, :update?
    return unless valid_update_params?

    settings = Form::AdminSettings.new(setting_attributes)
    return render_error(settings.errors.full_messages.to_sentence, 'INVALID_PARAM', 400, id: INVALID_PARAM_ID) unless settings.save

    Setting.misskey_compat_notes_per_one_ad = params[:notesPerOneAd] if params.key?(:notesPerOneAd)
    head 204
  end

  private

  def valid_update_params?
    STRING_SETTINGS.each_key.all? { |key| !params.key?(key) || require_string_param!(key, nullable: true) } &&
      %i(disableRegistration enableHcaptcha).all? { |key| params[key].nil? || require_boolean_param!(key) } &&
      require_integer_param!(:notesPerOneAd)
  end

  def setting_attributes
    attributes = STRING_SETTINGS.each_with_object({}) do |(key, setting), result|
      result[setting] = params[key] if params[key].is_a?(String)
    end
    attributes[:site_short_description] = '' if params.key?(:description) && params[:description].nil?
    attributes[:registrations_mode] = registrations_mode unless params[:disableRegistration].nil?
    attributes[:captcha_enabled] = params[:enableHcaptcha] ? '1' : '0' unless params[:enableHcaptcha].nil?
    attributes
  end

  def registrations_mode
    return 'none' if params[:disableRegistration]

    Setting.registrations_mode == 'none' ? 'open' : Setting.registrations_mode
  end

  def captcha_active?
    Setting.captcha_enabled && Rails.configuration.x.captcha.site_key.present? && Rails.configuration.x.captcha.secret_key.present?
  end

  def admin_meta
    retention = Setting.content_cache_retention_period.to_i

    {
      inquiryUrl: nil,
      enableHcaptcha: captcha_active?,
      hcaptchaSiteKey: Rails.configuration.x.captcha.site_key.presence,
      enableTestcaptcha: false,
      googleAnalyticsMeasurementId: nil,
      app192IconUrl: nil,
      app512IconUrl: nil,
      pinnedUsers: [],
      hiddenTags: [],
      blockedHosts: DomainBlock.where(severity: :suspend).order(:domain).pluck(:domain),
      silencedHosts: DomainBlock.where(severity: :silence).order(:domain).pluck(:domain),
      mediaSilencedHosts: DomainBlock.where(reject_media: true).order(:domain).pluck(:domain),
      sensitiveWords: [],
      prohibitedWords: [],
      prohibitedWordsForNameOfUser: [],
      preservedUsernames: UsernameBlock.order(:username).pluck(:username),
      hcaptchaSecretKey: nil,
      mcaptchaSecretKey: nil,
      recaptchaSecretKey: nil,
      turnstileSecretKey: nil,
      sensitiveMediaDetection: 'none',
      sensitiveMediaDetectionSensitivity: 'medium',
      setSensitiveFlagAutomatically: false,
      enableSensitiveMediaDetectionForVideos: false,
      sensitiveMediaDetectionApiUrl: nil,
      sensitiveMediaDetectionApiKey: nil,
      sensitiveMediaDetectionTimeout: 0,
      sensitiveMediaDetectionMaxImagesPerRequest: 0,
      proxyAccountId: nil,
      email: nil,
      smtpSecure: false,
      smtpHost: nil,
      smtpPort: nil,
      smtpUser: nil,
      smtpPass: nil,
      swPrivateKey: nil,
      useObjectStorage: false,
      objectStorageBaseUrl: nil,
      objectStorageBucket: nil,
      objectStoragePrefix: nil,
      objectStorageEndpoint: nil,
      objectStorageRegion: nil,
      objectStoragePort: nil,
      objectStorageAccessKey: nil,
      objectStorageSecretKey: nil,
      objectStorageUseSSL: false,
      objectStorageUseProxy: false,
      objectStorageSetPublicRead: false,
      objectStorageS3ForcePathStyle: false,
      deeplAuthKey: nil,
      deeplIsPro: false,
      enableIpLogging: true,
      enableActiveEmailValidation: false,
      enableVerifymailApi: false,
      verifymailAuthKey: nil,
      enableTruemailApi: false,
      truemailInstance: nil,
      truemailAuthKey: nil,
      enableChartsForRemoteUser: true,
      enableChartsForFederatedInstances: true,
      enableStatsForFederatedInstances: true,
      enableServerMachineStats: false,
      enableIdenticonGeneration: false,
      bannedEmailDomains: EmailDomainBlock.order(:domain).pluck(:domain),
      manifestJsonOverride: '',
      enableFanoutTimeline: true,
      enableFanoutTimelineDbFallback: true,
      perLocalUserUserTimelineCacheMax: 0,
      perRemoteUserUserTimelineCacheMax: 0,
      perUserHomeTimelineCacheMax: 0,
      perUserListTimelineCacheMax: 0,
      enableReactionsBuffering: false,
      summalyProxy: nil,
      urlPreviewEnabled: true,
      urlPreviewAllowRedirect: true,
      urlPreviewTimeout: 0,
      urlPreviewMaximumContentLength: 0,
      urlPreviewRequireContentLength: false,
      urlPreviewUserAgent: nil,
      urlPreviewSummaryProxyUrl: nil,
      urlPreviewSensitiveList: [],
      federation: limited_federation_mode? ? 'specified' : 'all',
      federationHosts: limited_federation_mode? ? DomainAllow.order(:domain).pluck(:domain) : [],
      deliverSuspendedSoftware: [],
      singleUserMode: Rails.configuration.x.single_user_mode,
      ugcVisibilityForVisitor: 'all',
      proxyRemoteFiles: false,
      signToActivityPubGet: true,
      allowExternalApRedirect: false,
      enableRemoteNotesCleaning: retention.positive?,
      remoteNotesCleaningExpiryDaysForEachNotes: retention,
      remoteNotesCleaningMaxProcessingDurationInMinutes: 0,
      showRoleBadgesOfRemoteUsers: false,
    }
  end
end
