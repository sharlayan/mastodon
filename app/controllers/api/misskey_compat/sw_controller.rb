# frozen_string_literal: true

class Api::MisskeyCompat::SwController < Api::MisskeyCompat::BaseController
  requires_write_scope :register, :unregister

  before_action :require_user!

  def register
    endpoint = params[:endpoint].to_s
    auth = params[:auth].to_s
    publickey = params[:publickey].to_s
    return render_error('endpoint required', 'INVALID_PARAM', 400) if endpoint.blank? || auth.blank? || publickey.blank?

    subscription, already = MisskeyCompat::SwRegistration.register(
      user: current_user,
      access_token_id: current_token.id,
      endpoint: endpoint,
      auth: auth,
      publickey: publickey
    )

    render json: MisskeyCompat::SwRegistration.response_for(subscription, already, current_account)
  end

  def unregister
    endpoint = params[:endpoint].to_s
    return render_error('endpoint required', 'INVALID_PARAM', 400) if endpoint.blank?

    Web::PushSubscription.where(user_id: current_user.id, endpoint: endpoint).destroy_all
    head 204
  end

  def show_registration
    endpoint = params[:endpoint].to_s
    subscription = Web::PushSubscription.find_by(user_id: current_user.id, endpoint: endpoint) if endpoint.present?
    return render json: nil if subscription.nil?

    render json: {
      userId: MisskeyCompat::MiId.encode(current_account.id),
      endpoint: subscription.endpoint,
      sendReadMessage: false,
    }
  end
end
