# frozen_string_literal: true

class Api::MisskeyCompat::SwController < Api::MisskeyCompat::BaseController
  before_action :require_user!

  PUSH_TYPES = %i(mention status reblog follow follow_request follow_accepted favourite reaction poll quote).freeze

  def register
    endpoint = params[:endpoint].to_s
    auth = params[:auth].to_s
    publickey = params[:publickey].to_s
    return render_error('endpoint required', 'INVALID_PARAM', 400) if endpoint.blank? || auth.blank? || publickey.blank?

    subscription = current_token.web_push_subscriptions.find_by(endpoint: endpoint)
    already = subscription.present?

    if already
      subscription.update!(key_auth: auth, key_p256dh: publickey, data: subscription_data(subscription.data))
    else
      subscription = current_token.web_push_subscriptions.create!(
        user: current_user,
        endpoint: endpoint,
        key_auth: auth,
        key_p256dh: publickey,
        standard: true,
        data: subscription_data
      )
    end

    render json: {
      state: already ? 'already-subscribed' : 'subscribed',
      key: Rails.configuration.x.vapid.public_key.presence,
      userId: current_account.id.to_s,
      endpoint: subscription.endpoint,
      sendReadMessage: false,
    }
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
      userId: current_account.id.to_s,
      endpoint: subscription.endpoint,
      sendReadMessage: false,
    }
  end

  private

  def subscription_data(existing = nil)
    base = existing.is_a?(Hash) ? existing.deep_dup : {}
    base['policy'] = 'all'
    base['alerts'] = PUSH_TYPES.index_with { true }.transform_keys(&:to_s)
    base['compat'] = 'misskey'
    base
  end
end
