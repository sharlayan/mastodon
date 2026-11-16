# frozen_string_literal: true

class Api::MisskeyCompat::Admin::SystemWebhooksController < Api::MisskeyCompat::Admin::ServerBaseController
  EVENT_MAP = {
    'abuseReport' => 'report.created',
    'abuseReportResolved' => 'report.updated',
    'userCreated' => 'account.created',
  }.freeze
  MISSKEY_EVENTS = %w(abuseReport abuseReportResolved userCreated inactiveModeratorsWarning inactiveModeratorsInvitationOnlyChanged).freeze
  DUMMY_TIME = Time.utc(2000, 1, 1)

  misskey_admin_endpoint :index, :show, :create, :update, :destroy, kind: 'write:admin:system-webhook', permission: :manage_webhooks, secure: true
  misskey_admin_endpoint :test, kind: 'read:admin:system-webhook', permission: :manage_webhooks, secure: true

  before_action :set_webhook, only: [:show, :update, :destroy]

  def index
    authorize :webhook, :index?
    return unless require_boolean_param!(:isActive) && require_string_array_param!(:on)

    scope = Webhook.order(:id)
    scope = scope.where(enabled: params[:isActive]) unless params[:isActive].nil?
    scope = scope.where('events && ARRAY[?]::varchar[]', EVENT_MAP.values_at(*params[:on]).compact.presence || ['']) if params[:on].present?

    render json: scope.map { |webhook| serialize(webhook) }
  end

  def show
    authorize @webhook, :show?

    render json: serialize(@webhook)
  end

  def create
    authorize :webhook, :create?
    return unless valid_webhook_params?

    webhook = Webhook.new(url: params[:url], events: mapped_events, enabled: params[:isActive], secret: params[:secret].presence)
    webhook.current_account = current_account
    Webhook.transaction do
      webhook.save!
      MisskeySystemWebhook.create!(webhook: webhook, name: params[:name])
    end

    render json: serialize(webhook)
  end

  def update
    authorize @webhook, :update?
    return unless require_keys!(:id) && valid_webhook_params?

    @webhook.assign_attributes(url: params[:url], enabled: params[:isActive], events: (@webhook.events - EVENT_MAP.values) + mapped_events)
    @webhook.secret = params[:secret] if params[:secret].present?
    @webhook.current_account = current_account
    Webhook.transaction do
      @webhook.save!
      MisskeySystemWebhook.find_or_initialize_by(webhook: @webhook).update!(name: params[:name])
    end

    render json: serialize(@webhook)
  end

  def destroy
    authorize @webhook, :destroy?

    @webhook.destroy!
    head 204
  end

  def test
    authorize :webhook, :show?
    webhook = Webhook.find_by(id: params[:webhookId]) if params[:webhookId].present?
    return render_error('No such webhook', 'NO_SUCH_WEBHOOK', 404, id: '0c52149c-e913-18f8-5dc7-74870bfe0cf9') if webhook.nil?
    return render_invalid_param('#/properties/type', "must be one of #{MISSKEY_EVENTS.join(', ')}") unless MISSKEY_EVENTS.include?(params[:type])
    return render_unmappable_events([params[:type]]) unless EVENT_MAP.key?(params[:type])
    return unless (override = test_override)

    MisskeyCompatSystemWebhookTestWorker.perform_async(webhook.id.to_s, test_payload(EVENT_MAP[params[:type]]), override)
    head 204
  end

  private

  def set_webhook
    id = mi_id_param(:id)
    @webhook = Webhook.find_by(id: id) if id.present?
    render_error('No such SystemWebhook', 'NO_SUCH_SYSTEM_WEBHOOK', 404, id: '38dd1ffe-04b4-6ff5-d8ba-4e6a6ae22c9d', kind: 'server') if @webhook.nil?
  end

  def valid_webhook_params?
    return false unless require_keys!(:isActive, :name, :on, :url)
    return false unless require_boolean_param!(:isActive) && require_string_param!(:name, min_length: 1) && require_string_param!(:url, min_length: 1)
    return false unless require_string_array_param!(:on, required: true) && (!params.key?(:secret) || require_string_param!(:secret))
    return render_invalid_param('#/properties/name', 'must NOT have more than 255 characters') && false if params[:name].length > 255
    return render_invalid_param('#/properties/on', "must be one of #{MISSKEY_EVENTS.join(', ')}") && false unless (params[:on] - MISSKEY_EVENTS).empty?

    unmappable = params[:on] - EVENT_MAP.keys
    return true if unmappable.empty?

    render_unmappable_events(unmappable)
    false
  end

  def render_unmappable_events(events)
    render_invalid_param('#/properties/on', "#{events.uniq.join(', ')} cannot be delivered by this server")
  end

  def mapped_events
    EVENT_MAP.values_at(*params[:on]).uniq
  end

  def test_override
    override = params[:override]
    return {} if override.nil?
    return render_invalid_param('#/properties/override', 'must be object') && nil unless override.is_a?(ActionController::Parameters)

    url = override[:url]
    return render_invalid_param('#/properties/override/properties/url', 'must be an http(s) URL') && nil if url.present? && !http_url?(url)

    { 'url' => url.presence, 'secret' => override[:secret].presence }.compact
  end

  def http_url?(value)
    value.is_a?(String) && Addressable::URI.parse(value).then { |uri| %w(http https).include?(uri.scheme) && uri.host.present? }
  rescue Addressable::URI::InvalidURIError
    false
  end

  def serialize(webhook)
    {
      id: MisskeyCompat::MiId.encode(webhook.id),
      isActive: webhook.enabled?,
      updatedAt: webhook.updated_at.iso8601,
      latestSentAt: nil,
      latestStatus: nil,
      name: MisskeySystemWebhook.find_by(webhook_id: webhook.id)&.name || Addressable::URI.parse(webhook.url).host.to_s,
      on: EVENT_MAP.select { |_misskey, mastodon| webhook.events.include?(mastodon) }.keys,
      url: webhook.url,
      secret: webhook.secret,
    }
  end

  def test_payload(event)
    object = event.start_with?('report.') ? dummy_report(event) : dummy_admin_account
    { event: event, created_at: DUMMY_TIME.iso8601(3), object: object }.to_json
  end

  def dummy_report(event)
    {
      id: '1',
      action_taken: event == 'report.updated',
      action_taken_at: event == 'report.updated' ? DUMMY_TIME.iso8601(3) : nil,
      category: 'other',
      comment: 'This is a dummy report for testing purposes',
      forwarded: false,
      created_at: DUMMY_TIME.iso8601(3),
      updated_at: DUMMY_TIME.iso8601(3),
      account: dummy_admin_account(id: '1', username: 'dummy1'),
      target_account: dummy_admin_account(id: '2', username: 'dummy2'),
      assigned_account: nil,
      action_taken_by_account: nil,
      statuses: [],
      rules: [],
    }
  end

  def dummy_admin_account(id: '1', username: 'dummy1')
    {
      id: id,
      username: username,
      domain: nil,
      created_at: DUMMY_TIME.iso8601(3),
      email: "#{username}@example.com",
      ip: nil,
      ips: [],
      locale: 'en',
      invite_request: nil,
      role: nil,
      confirmed: true,
      approved: true,
      disabled: false,
      silenced: false,
      suspended: false,
      account: { id: id, username: username, acct: username, display_name: username, created_at: DUMMY_TIME.iso8601(3), note: '', url: "https://example.com/@#{username}" },
    }
  end
end
