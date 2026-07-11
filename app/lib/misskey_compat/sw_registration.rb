# frozen_string_literal: true

module MisskeyCompat
  module SwRegistration
    PUSH_TYPES = %i(mention status reblog follow follow_request follow_accepted favourite reaction poll quote).freeze

    module_function

    def register(user:, access_token_id:, endpoint:, auth:, publickey:)
      scope = Web::PushSubscription.where(user_id: user.id, endpoint: endpoint)
      subscription = scope.find_by(access_token_id: access_token_id) || scope.order(id: :desc).first
      already = subscription.present?

      scope.where.not(id: subscription.id).delete_all if subscription

      if already
        subscription.update!(access_token_id: access_token_id, key_auth: auth, key_p256dh: publickey, data: subscription_data(subscription.data))
      else
        subscription = Web::PushSubscription.create!(
          user: user,
          access_token_id: access_token_id,
          endpoint: endpoint,
          key_auth: auth,
          key_p256dh: publickey,
          standard: true,
          data: subscription_data
        )
      end

      [subscription, already]
    end

    def response_for(subscription, already, account)
      {
        state: already ? 'already-subscribed' : 'subscribed',
        key: Rails.configuration.x.vapid.public_key.presence,
        userId: MisskeyCompat::MiId.encode(account.id),
        endpoint: subscription.endpoint,
        sendReadMessage: false,
      }
    end

    def subscription_data(existing = nil)
      base = existing.is_a?(Hash) ? existing.deep_dup : {}
      base['policy'] = 'all'
      base['alerts'] = PUSH_TYPES.index_with { true }.transform_keys(&:to_s)
      base['compat'] = 'misskey'
      base
    end
  end
end
