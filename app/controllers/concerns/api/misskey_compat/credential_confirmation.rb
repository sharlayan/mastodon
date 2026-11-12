# frozen_string_literal: true

module Api::MisskeyCompat::CredentialConfirmation
  extend ActiveSupport::Concern

  include Sharlayan::SecondFactorAttemptLimit

  INTERNAL_ERROR_ID = '5d37dbcb-891e-41ca-a3d6-e690c97775ac'
  # rubocop:disable I18n/RailsI18n/DecorateString
  INTERNAL_ERROR_MESSAGE = 'Internal error occurred. Please contact us if the error persists.'
  INCORRECT_PASSWORD_MESSAGE = 'Incorrect password.'
  # rubocop:enable I18n/RailsI18n/DecorateString

  private

  def confirm_credentials!(password, incorrect_password_id: nil)
    return false if rate_limited?(:misskey_compat_signin)
    return false unless confirm_second_factor!
    return true if password.is_a?(String) && current_user.encrypted_password.present? && current_user.valid_password?(password)

    if incorrect_password_id.nil?
      render_internal_error('incorrect password')
    else
      render_error(INCORRECT_PASSWORD_MESSAGE, 'INCORRECT_PASSWORD', 400, id: incorrect_password_id)
      false
    end
  end

  def confirm_second_factor!
    return true unless current_user.otp_enabled?

    token = params[:token]
    return render_internal_error('authentication failed') unless token.is_a?(String) && token.present?

    if second_factor_attempts_exceeded?(current_user)
      render_error(I18n.t('errors.429'), 'RATE_LIMIT_EXCEEDED', 429)
      return false
    end

    if current_user.validate_and_consume_otp!(token) || current_user.invalidate_otp_backup_code!(token)
      clear_second_factor_attempts(current_user)
      true
    else
      notify_failed_second_factor(current_user)
      render_internal_error('authentication failed')
    end
  end

  def render_internal_error(message)
    render_error(INTERNAL_ERROR_MESSAGE, 'INTERNAL_ERROR', 500,
                 id: INTERNAL_ERROR_ID, kind: 'server', info: { e: { message: message, code: 'Error', id: SecureRandom.uuid } })
    false
  end

  def require_string_params!(*names, optional: [])
    names.each do |name|
      next if params[name].is_a?(String)

      if params.key?(name)
        render_invalid_param("#/properties/#{name}/type", 'must be string')
      else
        render_invalid_param('#/required', "must have required property '#{name}'")
      end
      return false
    end

    optional.each do |name|
      next if params[name].nil? || params[name].is_a?(String)

      render_invalid_param("#/properties/#{name}/type", 'must be string')
      return false
    end

    true
  end
end
