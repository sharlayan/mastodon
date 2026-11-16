# frozen_string_literal: true

class Api::MisskeyCompat::AvailabilityController < Api::MisskeyCompat::BaseController
  LOCAL_USERNAME_PATTERN = /\A\w{1,20}\z/

  EMAIL_ERROR_REASONS = {
    invalid: 'format',
    unreachable: 'mx',
    blocked: 'banned',
    taken: 'banned',
  }.freeze

  before_action :require_object_body!
  before_action :enforce_rate_limit!

  def username
    username = params[:username]
    return render_invalid_param('#/properties/username/type', 'must be string') unless username.is_a?(String)
    return render_invalid_param('#/properties/username/pattern', 'must match pattern "^\\w{1,20}$"') unless username.match?(LOCAL_USERNAME_PATTERN)

    account = Account.new(username: username)
    UniqueUsernameValidator.new.validate(account)
    UnreservedUsernameValidator.new.validate(account)

    render json: { available: account.errors.empty? }
  end

  def email_address
    email = params[:emailAddress]
    return render_invalid_param('#/properties/emailAddress/type', 'must be string') unless email.is_a?(String)

    reason = email_unavailable_reason(email.strip)
    render json: { available: reason.nil?, reason: reason }
  end

  private

  def require_object_body!
    object_body!
  end

  def enforce_rate_limit!
    rate_limited?(:misskey_compat_signup_check)
  end

  def email_unavailable_reason(email)
    user = User.new(email: email, sign_up_ip: request.remote_ip)

    EmailAddressValidator.new(attributes: [:email]).validate_each(user, :email, email)
    return 'format' if user.errors.any?
    return 'used' if User.where(User.arel_table[:email].lower.eq(email.downcase)).exists?

    UserEmailValidator.new.validate(user)
    EmailMxValidator.new(attributes: [:email], attempt_ip: :sign_up_ip).validate_each(user, :email, email) if user.errors.empty? && !User.skip_mx_check?

    detail = user.errors.details[:email].first
    detail && EMAIL_ERROR_REASONS.fetch(detail[:error], 'format')
  end
end
