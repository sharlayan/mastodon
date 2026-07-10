# frozen_string_literal: true

class Api::MisskeyCompat::MetaController < Api::MisskeyCompat::BaseController
  def show
    return unless object_body!

    detail = detail_param
    return if performed?

    render json: detail ? detailed_meta : lite_meta
  end

  def endpoints
    render json: self.class.compat_endpoint_names
  end

  def self.compat_endpoint_names
    @compat_endpoint_names ||= Rails.application.routes.routes.filter_map do |route|
      controller = route.defaults[:controller]
      next unless controller&.start_with?('api/misskey_compat')

      path = route.path.spec.to_s.delete_suffix('(.:format)')
      next if path.include?(':')

      path.delete_prefix('/api/').presence
    end.uniq
  end

  private

  def detail_param
    value = params[:detail]
    return true if value.nil?
    return value if [true, false].include?(value)

    render_invalid_param('#/properties/detail/type', 'must be boolean')
    nil
  end

  def lite_meta
    {
      maintainerName: Setting.site_contact_username.presence,
      maintainerEmail: Setting.site_contact_email.presence,
      version: '13.0.0-compat',
      providesTarball: false,
      name: Setting.site_title,
      shortName: nil,
      uri: root_url.chomp('/'),
      description: Setting.site_short_description.presence || Setting.site_description.presence,
      langs: [Setting.default_locale].compact,
      tosUrl: nil,
      repositoryUrl: nil,
      feedbackUrl: nil,
      impressumUrl: nil,
      privacyPolicyUrl: nil,
      disableRegistration: Setting.registrations_mode == 'none',
      emailRequiredForSignup: false,
      enableHcaptcha: false,
      hcaptchaSiteKey: nil,
      enableMcaptcha: false,
      mcaptchaSiteKey: nil,
      mcaptchaInstanceUrl: nil,
      enableRecaptcha: false,
      recaptchaSiteKey: nil,
      enableTurnstile: false,
      turnstileSiteKey: nil,
      swPublickey: Rails.configuration.x.vapid.public_key.presence,
      themeColor: Setting.theme_color.presence,
      mascotImageUrl: upload_url(instance_presenter.mascot),
      bannerUrl: upload_url(instance_presenter.thumbnail, style: :'@1x'),
      infoImageUrl: nil,
      serverErrorImageUrl: nil,
      notFoundImageUrl: nil,
      iconUrl: upload_url(instance_presenter.app_icon) || upload_url(instance_presenter.favicon),
      backgroundImageUrl: nil,
      logoImageUrl: nil,
      maxNoteTextLength: StatusLengthValidator::MAX_CHARS,
      defaultLightTheme: nil,
      defaultDarkTheme: nil,
      ads: [],
      notesPerOneAd: 0,
      enableEmail: true,
      enableServiceWorker: Rails.configuration.x.vapid.public_key.present?,
      translatorAvailable: false,
      serverRules: Rule.ordered.pluck(:text),
      policies: compat_policies,
      mediaProxy: nil,
      enableUrlPreview: true,
    }
  end

  def detailed_meta
    lite_meta.merge(
      cacheRemoteFiles: true,
      cacheRemoteSensitiveFiles: false,
      requireSetup: false,
      proxyAccountName: nil,
      features: {
        localTimeline: true,
        globalTimeline: true,
        registration: Setting.registrations_mode != 'none',
        emailRequiredForSignup: false,
        hcaptcha: false,
        recaptcha: false,
        turnstile: false,
        objectStorage: false,
        serviceWorker: Rails.configuration.x.vapid.public_key.present?,
        miauth: true,
      }
    )
  end

  def upload_url(upload, style: :original)
    return nil if upload.nil?

    full_asset_url(upload.file.url(style))
  end

  def instance_presenter
    @instance_presenter ||= InstancePresenter.new
  end
end
