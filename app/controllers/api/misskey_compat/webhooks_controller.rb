# frozen_string_literal: true

class Api::MisskeyCompat::WebhooksController < Api::MisskeyCompat::BaseController
  NO_SUCH_WEBHOOK_IDS = {
    'show' => '50f614d9-3047-4f7e-90d8-ad6b2d5fb098',
    'update' => 'fb0fea69-da18-45b1-828d-bd4fd1612518',
    'destroy' => 'bae73e5a-5522-4965-ae19-3a8688e71d82',
    'test' => '0c52149c-e913-18f8-5dc7-74870bfe0cf9',
  }.freeze
  TOO_MANY_WEBHOOKS_ID = '87a9bb19-111e-4e37-81d3-a3e7426453b0'

  requires_write_scope :create, :update, :destroy
  requires_misskey_permission 'read:account', :index, :show, :test
  requires_misskey_permission 'write:account', :create, :update, :destroy

  before_action :require_user!
  before_action :require_native_user_token!, only: :test
  before_action :require_object_body!, except: :index
  before_action :set_webhook, only: [:show, :update, :destroy, :test]

  def index
    render json: current_account_webhooks.order(:id).map { |webhook| serialize(webhook) }
  end

  def show
    render json: serialize(@webhook)
  end

  def create
    return unless valid_strings?(name: true, url: true) && valid_events?(required: true) && valid_secret?
    return render_error('You cannot create webhook any more', 'TOO_MANY_WEBHOOKS', 400, id: TOO_MANY_WEBHOOKS_ID) if current_account_webhooks.count >= MisskeyWebhook::LIMIT

    webhook = MisskeyWebhook.create!(account: current_account, name: params[:name], url: params[:url], secret: params[:secret].to_s, events: params[:on].uniq)
    render json: serialize(webhook)
  end

  def update
    return unless valid_strings?(name: false, url: false) && valid_events?(required: false) && valid_secret?(nullable: true) && valid_active?

    attributes = { name: params[:name], url: params[:url], events: params[:on]&.uniq, active: params[:active] }.compact
    attributes[:secret] = params[:secret].to_s if params.key?(:secret)
    @webhook.update!(attributes)
    head 204
  end

  def destroy
    @webhook.destroy!
    head 204
  end

  def test
    type = params[:type]
    return render_invalid_param('#/properties/type', 'must be one of the webhook event types') unless MisskeyWebhook::EVENTS.include?(type)
    return unless (override = test_override)
    return if rate_limited?(:misskey_compat_webhook_test)

    content = MisskeyCompat::WebhookTestContent.for(type)
    MisskeyCompatWebhookDeliveryWorker.set(retry: false).perform_async(@webhook.id.to_s, MisskeyCompatWebhookEventWorker.payload(@webhook, type, content), override) unless content.nil?
    head 204
  end

  private

  def current_account_webhooks
    MisskeyWebhook.where(account: current_account)
  end

  def set_webhook
    @webhook = current_account_webhooks.find_by(id: params[:webhookId]) if compat_id?(params[:webhookId])
    render_error('No such webhook', 'NO_SUCH_WEBHOOK', 404, id: NO_SUCH_WEBHOOK_IDS[action_name]) if @webhook.nil?
  end

  def require_object_body!
    object_body!
  end

  def serialize(webhook)
    {
      id: MisskeyCompat::MiId.encode(webhook.id),
      userId: MisskeyCompat::MiId.encode(webhook.account_id),
      name: webhook.name,
      on: webhook.events,
      url: webhook.url,
      secret: webhook.secret,
      active: webhook.active,
      latestSentAt: webhook.latest_sent_at&.iso8601(3),
      latestStatus: webhook.latest_status,
    }
  end

  def valid_strings?(name:, url:)
    { name: [name, 100], url: [url, 1024] }.each do |key, (required, max)|
      next if !params.key?(key) && !required

      value = params[key]
      next if value.is_a?(String) && value.length.between?(1, max)

      render_invalid_param("#/properties/#{key}", "must be a string of 1 to #{max} characters")
      return false
    end

    true
  end

  def valid_events?(required:)
    return true if !params.key?(:on) && !required

    events = params[:on]
    return true if events.is_a?(Array) && events.all? { |event| MisskeyWebhook::EVENTS.include?(event) }

    render_invalid_param('#/properties/on', 'must be an array of webhook event types')
    false
  end

  def valid_secret?(nullable: false)
    value = params[:secret]
    return true if !params.key?(:secret) || (value.nil? && nullable) || (value.is_a?(String) && value.length <= 1024)

    render_invalid_param('#/properties/secret', 'must be a string of at most 1024 characters')
    false
  end

  def valid_active?
    return true if !params.key?(:active) || [true, false].include?(params[:active])

    render_invalid_param('#/properties/active', 'must be boolean')
    false
  end

  def test_override
    raw = params[:override]
    return {} if raw.nil?
    return invalid_override unless raw.is_a?(ActionController::Parameters)

    override = raw.permit(:url, :secret).to_h.to_hash
    return invalid_override unless override.values.all?(String)
    return invalid_override if override.key?('url') && !valid_webhook_url?(override['url'])

    override
  end

  def invalid_override
    render_invalid_param('#/properties/override', 'must be an object with an http(s) url and a string secret')
    nil
  end

  def valid_webhook_url?(url)
    uri = Addressable::URI.parse(url)
    URLValidator::VALID_SCHEMES.include?(uri.scheme) && uri.host.present?
  rescue Addressable::URI::InvalidURIError
    false
  end
end
