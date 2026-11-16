# frozen_string_literal: true

class Api::MisskeyCompat::TwoFactorController < Api::MisskeyCompat::BaseController
  include Redisable
  include Api::MisskeyCompat::CredentialConfirmation

  PENDING_SECRET_TTL = 1.hour
  CHALLENGE_TTL = 5.minutes
  KEY_NAME_LENGTH = (1..30)
  QR_SIZE = 240

  INCORRECT_PASSWORD_IDS = {
    'register' => '78d6c839-20c9-4c66-b90a-fc0542168b48',
    'unregister' => '7add0395-9901-4098-82f9-4f67af65f775',
    'register_key' => '38769596-efe2-4faf-9bec-abbb3f2cd9ba',
    'key_done' => '0d7ec6d2-e652-443e-a7bf-9ee9a0cd77b0',
    'remove_key' => '141c598d-a825-44c8-9173-cfb9d92be493',
  }.freeze

  TWO_FACTOR_NOT_ENABLED_IDS = {
    'register_key' => 'bf32b864-449b-47b8-974e-f9a5468546f1',
    'key_done' => '798d6847-b1ed-4f9c-b1f9-163c42655995',
  }.freeze

  NO_SUCH_KEY_ID = 'f9c5467f-d492-4d3c-9a8g-a70dacc86512'
  # rubocop:disable I18n/RailsI18n/DecorateString
  NO_SUCH_KEY_MESSAGE = 'No such key.'
  KEY_ACCESS_DENIED_MESSAGE = 'You do not have edit privilege of this key.'
  # rubocop:enable I18n/RailsI18n/DecorateString
  KEY_ACCESS_DENIED_ID = '1fb7cb09-d46a-4fff-b8df-057708cce513'

  ACTIONS = %i(register done unregister register_key key_done remove_key update_key).freeze

  requires_write_scope(*ACTIONS)
  requires_misskey_permission 'write:account', *ACTIONS

  before_action :require_user!
  before_action :require_native_user_token!
  before_action :require_object_body!

  def register
    return unless confirm_password!

    secret = User.generate_otp_secret
    with_redis { |r| r.set(pending_secret_key, secret, ex: PENDING_SECRET_TTL.to_i) }

    issuer = Rails.configuration.x.local_domain
    url = current_user.otp_provisioning_uri(current_account.username, otp_secret: secret, issuer: issuer)

    render json: {
      qr: RQRCode::QRCode.new(url).as_png(size: QR_SIZE).to_data_url,
      url: url,
      secret: secret,
      label: current_account.username,
      issuer: issuer,
    }
  end

  def done
    return unless require_string_params!(:token)
    return if rate_limited?(:misskey_compat_signin)

    secret = with_redis { |r| r.get(pending_secret_key) }
    return render_internal_error('two-factor setup has not been started') if secret.blank?
    return render_internal_error('not verified') unless current_user.validate_and_consume_otp!(params[:token].gsub(/\s/, ''), otp_secret: secret)

    current_user.otp_required_for_login = true
    current_user.otp_secret = secret
    backup_codes = current_user.generate_otp_backup_codes!
    current_user.save!
    with_redis { |r| r.del(pending_secret_key) }

    UserMailer.two_factor_enabled(current_user).deliver_later!

    render json: { backupCodes: backup_codes }
  end

  def unregister
    return unless confirm_password!

    enabled = current_user.otp_enabled?
    current_user.disable_two_factor!
    UserMailer.two_factor_disabled(current_user).deliver_later! if enabled

    head 204
  end

  def register_key
    return unless confirm_password!
    return two_factor_not_enabled unless current_user.otp_enabled?

    current_user.update(webauthn_id: WebAuthn.generate_user_id) unless current_user.webauthn_id

    options = WebAuthn::Credential.options_for_create(
      user: {
        name: current_account.username,
        display_name: current_account.username,
        id: current_user.webauthn_id,
      },
      exclude: current_user.webauthn_credentials.pluck(:external_id),
      authenticator_selection: { user_verification: 'discouraged' }
    )

    with_redis { |r| r.set(challenge_key, options.challenge, ex: CHALLENGE_TTL.to_i) }

    render json: options
  end

  def key_done
    return unless valid_key_name?
    return render_invalid_param('#/properties/credential/type', 'must be object') unless params[:credential].is_a?(ActionController::Parameters)
    return unless confirm_password!
    return two_factor_not_enabled unless current_user.otp_enabled?

    challenge = with_redis { |r| r.getdel(challenge_key) }
    return render_internal_error('challenge not found') if challenge.blank?

    webauthn_credential = verified_webauthn_credential(challenge)
    return render_internal_error('verification failed') if webauthn_credential.nil?

    credential = current_user.webauthn_credentials.create!(
      external_id: webauthn_credential.id,
      public_key: webauthn_credential.public_key,
      nickname: params[:name],
      sign_count: webauthn_credential.sign_count
    )

    if current_user.webauthn_credentials.one?
      UserMailer.webauthn_enabled(current_user).deliver_later!
    else
      UserMailer.webauthn_credential_added(current_user, credential).deliver_later!
    end

    render json: { id: credential.external_id, name: credential.nickname }
  end

  def remove_key
    return unless require_string_params!(:credentialId)
    return unless confirm_password!

    credential = current_user.webauthn_credentials.find_by(external_id: params[:credentialId])

    if credential&.destroy
      if current_user.webauthn_credentials.empty?
        UserMailer.webauthn_disabled(current_user).deliver_later!
      else
        UserMailer.webauthn_credential_deleted(current_user, credential).deliver_later!
      end
    end

    render json: {}
  end

  def update_key
    return unless valid_key_name? && require_string_params!(:credentialId)

    credential = WebauthnCredential.find_by(external_id: params[:credentialId])
    return render_error(NO_SUCH_KEY_MESSAGE, 'NO_SUCH_KEY', 404, id: NO_SUCH_KEY_ID) if credential.nil?
    return render_error(KEY_ACCESS_DENIED_MESSAGE, 'ACCESS_DENIED', 403, id: KEY_ACCESS_DENIED_ID) if credential.user_id != current_user.id

    credential.update!(nickname: params[:name])

    render json: {}
  end

  private

  def require_object_body!
    object_body!
  end

  def confirm_password!
    require_string_params!(:password, optional: [:token]) &&
      confirm_credentials!(params[:password], incorrect_password_id: INCORRECT_PASSWORD_IDS.fetch(action_name))
  end

  def valid_key_name?
    return false unless require_string_params!(:name)
    return true if KEY_NAME_LENGTH.cover?(params[:name].length)

    if params[:name].length < KEY_NAME_LENGTH.min
      render_invalid_param('#/properties/name/minLength', "must NOT have fewer than #{KEY_NAME_LENGTH.min} characters")
    else
      render_invalid_param('#/properties/name/maxLength', "must NOT have more than #{KEY_NAME_LENGTH.max} characters")
    end
    false
  end

  def verified_webauthn_credential(challenge)
    webauthn_credential = WebAuthn::Credential.from_create(params[:credential].to_unsafe_h)
    webauthn_credential if webauthn_credential.verify(challenge)
  rescue WebAuthn::Error, ArgumentError, KeyError, TypeError
    nil
  end

  def two_factor_not_enabled
    render_error('2fa not enabled.', 'TWO_FACTOR_NOT_ENABLED', 400, id: TWO_FACTOR_NOT_ENABLED_IDS.fetch(action_name))
  end

  def pending_secret_key
    "misskey_compat:2fa:pending_secret:#{current_user.id}"
  end

  def challenge_key
    "misskey_compat:2fa:webauthn_challenge:#{current_user.id}"
  end
end
