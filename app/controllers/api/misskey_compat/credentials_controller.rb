# frozen_string_literal: true

class Api::MisskeyCompat::CredentialsController < Api::MisskeyCompat::BaseController
  include Auth::CaptchaConcern
  include Api::MisskeyCompat::CredentialConfirmation

  NO_SUCH_CODE_ID = '97c1f576-e4b8-4b8a-a6dc-9cb65e7f6f85'

  before_action :require_object_body!

  def request_reset_password
    return unless require_string_params!(:username, :email)
    return if rate_limited?(:misskey_compat_email_request)

    user = Account.find_local(params[:username])&.user
    user.send_reset_password_instructions if user&.confirmed? && user.email.casecmp?(params[:email].strip)

    head 204
  end

  def reset_password
    return unless require_string_params!(:token, :password)
    return if rate_limited?(:misskey_compat_signin)

    user = User.reset_password_by_token(reset_password_token: params[:token], password: params[:password], password_confirmation: params[:password])
    return render_internal_error('invalid reset token') if user.errors.include?(:reset_password_token) || !user.persisted?
    return render_error(user.errors.full_messages.to_sentence, 'INVALID_PARAM', 400) if user.errors.any?

    user.session_activations.destroy_all
    user.revoke_access!

    head 204
  end

  def verify_email
    return unless require_string_params!(:code)
    return if rate_limited?(:misskey_compat_signin)

    user = params[:code].present? ? User.find_first_by_auth_conditions(confirmation_token: params[:code]) : nil
    return no_such_code if user.nil?
    return render_error(I18n.t('errors.403'), 'ACCESS_DENIED', 403, id: ACCESS_DENIED_ID) if captcha_enabled? && !user.confirmed?

    user.confirm
    return no_such_code if user.errors.any?

    head 204
  end

  private

  def no_such_code
    render_error('No such code.', 'NO_SUCH_CODE', 404, id: NO_SUCH_CODE_ID) # rubocop:disable I18n/RailsI18n/DecorateString
  end

  def require_object_body!
    object_body!
  end
end
