# frozen_string_literal: true

class Web::LinkedPushNotificationWorker
  include Sidekiq::Worker
  include RoutingHelper

  sidekiq_options queue: 'push', retry: 3

  TTL     = Web::PushNotificationWorker::TTL
  URGENCY = Web::PushNotificationWorker::URGENCY

  def perform(main_user_id, notification_id)
    @main_user    = User.find_by(id: main_user_id)
    @notification = Notification.find_by(id: notification_id)

    return unless @main_user && @notification
    return if @notification.updated_at < TTL.ago
    return if @notification.activity.blank?

    subscriptions = Web::PushSubscription.where(user_id: @main_user.id)
    subscriptions.each do |subscription|
      send_push_for(subscription)
    rescue => e
      Rails.logger.warn { "LinkedPushNotificationWorker failed for subscription #{subscription.id}: #{e.message}" }
    end
  rescue ActiveRecord::RecordNotFound
    true
  end

  private

  def send_push_for(subscription)
    web_push_request = WebPushRequest.new(subscription)
    payload_json = I18n.with_locale(subscription.locale.presence || I18n.default_locale) do
      build_payload(subscription).to_json
    end

    if web_push_request.legacy
      perform_legacy_request(web_push_request, payload_json)
    else
      perform_standard_request(web_push_request, payload_json)
    end
  end

  def build_payload(subscription)
    {
      preferred_locale: subscription.locale.presence || I18n.default_locale,
      notification_type: @notification.type,
      icon: full_asset_url(@notification.from_account.avatar_static_url),
      title: I18n.t("notification_mailer.#{@notification.type}.subject",
                    name: @notification.from_account.display_name.presence || @notification.from_account.username,
                    default: @notification.from_account.display_name.presence || @notification.from_account.username),
      body: build_body,
    }
  end

  def build_body
    status = @notification.target_status
    if status
      str = ActionController::Base.helpers.strip_tags(status.spoiler_text.presence || status.text.presence || '')
      str.truncate(140)
    else
      ActionController::Base.helpers.strip_tags(@notification.from_account.note.to_s).truncate(140)
    end
  end

  def perform_legacy_request(web_push_request, payload_json)
    payload = web_push_request.legacy_encrypt(payload_json)

    RequestPool.current.with(web_push_request.audience) do |http_client|
      request = Request.new(:post, web_push_request.endpoint, body: payload.fetch(:ciphertext), http_client: http_client)
      request.add_headers(
        'Content-Type' => 'application/octet-stream',
        'Ttl' => TTL.to_s,
        'Urgency' => URGENCY,
        'Content-Encoding' => 'aesgcm',
        'Encryption' => "salt=#{Webpush.encode64(payload.fetch(:salt)).delete('=')}",
        'Crypto-Key' => "dh=#{Webpush.encode64(payload.fetch(:server_public_key)).delete('=')};#{web_push_request.crypto_key_header}",
        'Authorization' => web_push_request.legacy_authorization_header
      )
      send_request(request)
    end
  end

  def perform_standard_request(web_push_request, payload_json)
    payload = web_push_request.standard_encrypt(payload_json)

    RequestPool.current.with(web_push_request.audience) do |http_client|
      request = Request.new(:post, web_push_request.endpoint, body: payload, http_client: http_client)
      request.add_headers(
        'Content-Type' => 'application/octet-stream',
        'Ttl' => TTL.to_s,
        'Urgency' => URGENCY,
        'Content-Encoding' => 'aes128gcm',
        'Authorization' => web_push_request.standard_authorization_header,
        'Content-Length' => payload.length.to_s
      )
      send_request(request)
    end
  end

  def send_request(request)
    request.perform do |response|
      if (400..499).cover?(response.code) && ![408, 429].include?(response.code)
        Rails.logger.info { "LinkedPushNotificationWorker: subscription endpoint returned #{response.code}" }
      elsif !(200...300).cover?(response.code) && response.code != 507
        raise Mastodon::UnexpectedResponseError, response
      end
    end
  end
end
