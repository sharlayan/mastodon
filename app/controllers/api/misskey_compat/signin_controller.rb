# frozen_string_literal: true

class Api::MisskeyCompat::SigninController < Api::MisskeyCompat::BaseController
  NO_SUCH_USER_ID = '6cc579cc-885d-43d8-95c2-b8c7fc963280'
  SUSPENDED_ID = 'e03a5f46-d309-4865-9b69-56282d94e1eb'
  UNAVAILABLE_ID = 'b2c5a2f0-1d2f-4b0d-9d0a-1b8a6d7f0c11'
  INCORRECT_PASSWORD_ID = '932c904e-9460-45b7-9ce6-7ed33be7eb2c'
  INCORRECT_TOKEN_ID = 'cdf1235b-ac71-46d4-a3a6-84ccce48df6f'
  PASSKEY_UNSUPPORTED_ID = 'a4f3d0e2-6c8b-4a7d-8f2a-9c1e5b3d7a10'

  before_action :require_signin_flow_enabled!
  before_action :require_same_origin!

  def create
    return unless object_body!
    return if rate_limited?(:misskey_compat_signin)

    username = params[:username]
    return render_invalid_param('#/properties/username/type', 'must be string') unless username.is_a?(String)

    user = Account.find_local(username.strip.delete_prefix('@'))&.user
    return signin_error(404, NO_SUCH_USER_ID) if user.nil?
    return signin_error(403, SUSPENDED_ID) if user.account.suspended?
    return signin_error(403, UNAVAILABLE_ID) unless user.functional?

    password = params[:password]
    return render_next(user.two_factor_enabled? ? 'password' : 'captcha') if password.nil?
    return render_invalid_param('#/properties/password/type', 'must be string') unless password.is_a?(String)

    correct_password = user.external_or_valid_password?(password)

    unless user.two_factor_enabled?
      return correct_password ? render_finished(user) : signin_error(403, INCORRECT_PASSWORD_ID)
    end

    resolve_two_factor(user, correct_password)
  end

  private

  def require_signin_flow_enabled!
    render_error('This endpoint is not available', 'ENDPOINT_DISABLED', 404) unless Setting.misskey_compat_signin_flow_enabled
  end

  def require_same_origin!
    return if performed? || request.local?
    return if request.origin.present? && request.origin == request.base_url

    render_error('This endpoint is only available from the local origin', 'ORIGIN_NOT_ALLOWED', 403)
  end

  def resolve_two_factor(user, correct_password)
    token = params[:token]

    if token.present?
      return signin_error(403, INCORRECT_PASSWORD_ID) unless correct_password

      consume_otp(user, token.to_s) ? render_finished(user) : signin_error(403, INCORRECT_TOKEN_ID)
    elsif user.otp_required_for_login?
      return signin_error(403, INCORRECT_PASSWORD_ID) unless correct_password

      render_next('totp')
    else
      signin_error(400, PASSKEY_UNSUPPORTED_ID)
    end
  end

  def consume_otp(user, token)
    user.validate_and_consume_otp!(token) || user.invalidate_otp_backup_code!(token)
  end

  def render_next(next_step)
    render json: { finished: false, next: next_step }
  end

  def render_finished(user)
    token = MisskeyCompat::MiAuth.issue_token(user, name: 'Misskey web sign-in', scopes: MisskeyCompat::MiAuth::SCOPES)
    user.update_sign_in!(new_sign_in: true)
    render json: { finished: true, id: MisskeyCompat::MiId.encode(user.account_id), i: token.token }
  end

  def signin_error(status, id)
    render_error('Signin failed', 'SIGNIN_FAILED', status, id: id)
  end
end
