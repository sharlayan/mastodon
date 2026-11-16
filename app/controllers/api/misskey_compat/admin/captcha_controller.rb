# frozen_string_literal: true

class Api::MisskeyCompat::Admin::CaptchaController < Api::MisskeyCompat::Admin::ServerBaseController
  PROVIDERS = %w(none hcaptcha mcaptcha recaptcha turnstile testcaptcha).freeze

  misskey_admin_endpoint :show, kind: 'read:admin:meta', role: :admin, permission: :manage_settings
  misskey_admin_endpoint :update, kind: 'write:admin:meta', role: :admin, permission: :manage_settings

  def show
    authorize :settings, :show?

    render json: {
      provider: captcha_available? && Setting.captcha_enabled ? 'hcaptcha' : 'none',
      hcaptcha: { siteKey: captcha_config.site_key.presence, secretKey: nil },
      mcaptcha: { siteKey: nil, secretKey: nil, instanceUrl: nil },
      recaptcha: { siteKey: nil, secretKey: nil },
      turnstile: { siteKey: nil, secretKey: nil },
    }
  end

  def update
    authorize :settings, :update?
    return unless require_keys!(:provider)
    return render_invalid_param('#/properties/provider', "must be one of #{PROVIDERS.join(', ')}") unless PROVIDERS.include?(params[:provider])
    return unless %i(captchaResult sitekey secret instanceUrl).all? { |key| !params.key?(key) || require_string_param!(key, nullable: true) }

    case params[:provider]
    when 'none'
      Setting.captcha_enabled = false
    when 'hcaptcha'
      return render_captcha_error('INVALID_PARAMETERS', '26654194-410e-44e2-b42e-460ff6f92476', 'hCaptcha keys are configured by HCAPTCHA_SITE_KEY and HCAPTCHA_SECRET_KEY on this server') unless hcaptcha_keys_match?

      Setting.captcha_enabled = true
    else
      return render_captcha_error('INVALID_PROVIDER', '14bf7ae1-80cc-4363-acb2-4fd61d086af0', "#{params[:provider]} is not supported on this server")
    end

    head 204
  end

  private

  def captcha_config
    Rails.configuration.x.captcha
  end

  def captcha_available?
    captcha_config.site_key.present? && captcha_config.secret_key.present?
  end

  def hcaptcha_keys_match?
    return false unless captcha_available?

    [params[:sitekey].blank? || params[:sitekey] == captcha_config.site_key, params[:secret].blank? || ActiveSupport::SecurityUtils.secure_compare(params[:secret], captcha_config.secret_key)].all?
  end

  def render_captcha_error(code, id, message)
    render_error(message, code, 400, id: id)
  end
end
