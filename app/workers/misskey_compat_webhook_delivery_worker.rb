# frozen_string_literal: true

class MisskeyCompatWebhookDeliveryWorker
  include Sidekiq::Worker
  include JsonLdHelper

  sidekiq_options queue: 'push', retry: 16, dead: false

  NETWORK_ERROR_STATUS = 1

  def perform(webhook_id, body, override = {})
    @webhook = MisskeyWebhook.find(webhook_id)
    @url = override['url'].presence || @webhook.url
    @secret = override.key?('secret') ? override['secret'].to_s : @webhook.secret

    deliver(body)
  rescue ActiveRecord::RecordNotFound
    true
  end

  private

  def deliver(body)
    request = Request.new(:post, @url, body: body)
    request.add_headers(
      'Content-Type' => 'application/json',
      'X-Misskey-Host' => Rails.configuration.x.web_domain,
      'X-Misskey-Hook-Id' => MisskeyCompat::MiId.encode(@webhook.id),
      'X-Misskey-Hook-Secret' => @secret
    )

    request.perform do |response|
      @webhook.record_delivery!(response.code)
      raise Mastodon::UnexpectedResponseError, response unless response_successful?(response) || response_error_unsalvageable?(response)
    end
  rescue Mastodon::HostValidationError
    @webhook.record_delivery!(NETWORK_ERROR_STATUS)
  rescue HTTP::Error, OpenSSL::SSL::SSLError
    @webhook.record_delivery!(NETWORK_ERROR_STATUS)
    raise
  end
end
