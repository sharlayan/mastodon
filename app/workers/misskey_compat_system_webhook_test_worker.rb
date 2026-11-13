# frozen_string_literal: true

class MisskeyCompatSystemWebhookTestWorker < Webhooks::DeliveryWorker
  sidekiq_options queue: 'push', retry: false

  def perform(webhook_id, body, override = {})
    @webhook = Webhook.find(webhook_id).dup
    @webhook.url = override['url'] if override['url'].present?
    @webhook.secret = override['secret'] if override['secret'].present?
    @body = @webhook.template.blank? ? body : Webhooks::PayloadRenderer.new(body).render(@webhook.template)

    perform_request
  rescue ActiveRecord::RecordNotFound
    true
  end
end
