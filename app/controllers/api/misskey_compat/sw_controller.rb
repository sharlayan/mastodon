# frozen_string_literal: true

class Api::MisskeyCompat::SwController < Api::MisskeyCompat::BaseController
  NO_SUCH_REGISTRATION_ID = ' b09d8066-8064-5613-efb6-0e963b21d012'

  requires_write_scope :register, :unregister, :update_registration
  requires_misskey_permission 'read:notifications', :show_registration
  requires_misskey_permission 'write:notifications', :register, :unregister, :update_registration

  before_action :require_user!, except: :unregister
  before_action :require_user_if_authenticated!, only: :unregister
  before_action :require_native_user_token!, only: :update_registration

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
    return unless object_body!
    return if rate_limited?(:misskey_compat_push_unregister)

    endpoint = params[:endpoint].to_s
    subscriptions = Web::PushSubscription.all
    subscriptions = subscriptions.where(user_id: current_user.id) if current_user

    if current_user.nil? || params.key?(:auth) || params.key?(:publickey)
      %i(endpoint auth publickey).each do |key|
        return render_invalid_param("#/properties/#{key}", 'must be a non-empty string') unless params[key].is_a?(String) && params[key].present?
      end

      subscriptions = subscriptions.where(endpoint: params[:endpoint], key_auth: params[:auth], key_p256dh: params[:publickey])
    else
      subscriptions = endpoint.present? ? subscriptions.where(endpoint: endpoint) : subscriptions.where(access_token_id: current_token.id)
    end

    subscriptions.destroy_all
    head 204
  end

  def show_registration
    endpoint = params[:endpoint].to_s
    subscription = Web::PushSubscription.find_by(user_id: current_user.id, endpoint: endpoint) if endpoint.present?
    return render json: nil if subscription.nil?

    render json: registration_json(subscription)
  end

  def update_registration
    return unless object_body!

    endpoint = params[:endpoint]
    return render_invalid_param('#/properties/endpoint/type', 'must be string') unless endpoint.is_a?(String)
    return render_invalid_param('#/properties/sendReadMessage/type', 'must be boolean') unless params[:sendReadMessage].nil? || [true, false].include?(params[:sendReadMessage])

    subscription = Web::PushSubscription.find_by(user_id: current_user.id, endpoint: endpoint)
    return render_error('No such registration.', 'NO_SUCH_REGISTRATION', 404, id: NO_SUCH_REGISTRATION_ID) if subscription.nil? # rubocop:disable I18n/RailsI18n/DecorateString

    subscription.update!(data: (subscription.data || {}).merge('send_read_message' => params[:sendReadMessage])) unless params[:sendReadMessage].nil?

    render json: registration_json(subscription)
  end

  private

  def registration_json(subscription)
    {
      userId: MisskeyCompat::MiId.encode(current_account.id),
      endpoint: subscription.endpoint,
      sendReadMessage: MisskeyCompat::SwRegistration.send_read_message?(subscription),
    }
  end
end
