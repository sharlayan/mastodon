# frozen_string_literal: true

module Sharlayan::PushNotificationWorkerExtensions
  IGNORED_DOMAINS = ENV.fetch('PUSH_NOTIFICATION_IGNORED_DOMAINS', 'ntfy.sh').split(',').map(&:strip).reject(&:empty?).freeze

  private

  def push_notification_json
    return super unless @subscription.misskey_compat?

    I18n.with_locale(@subscription.locale.presence || I18n.default_locale) do
      MisskeyCompat::PushSerializer.serialize(@notification, @subscription.user.account).to_json
    end
  end

  def sharlayan_success_response?(response)
    if ignored_domain?
      Rails.logger.info { "Ignoring response for domain #{endpoint_domain}: #{response.code}" }
      true
    elsif response.code == 507
      Rails.logger.info { "Received 507 response for subscription #{@subscription.id}, treating as success" }
      true
    else
      false
    end
  end

  def ignored_domain?
    domain = endpoint_domain
    IGNORED_DOMAINS.include?(domain) if domain
  end

  def endpoint_domain
    return unless @subscription&.endpoint

    URI.parse(@subscription.endpoint).host
  rescue URI::InvalidURIError
    nil
  end
end
