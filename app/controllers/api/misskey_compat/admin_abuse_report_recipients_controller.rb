# frozen_string_literal: true

class Api::MisskeyCompat::AdminAbuseReportRecipientsController < Api::MisskeyCompat::BaseController
  include Api::MisskeyCompat::AdminModerationAccess

  WEBHOOK_EVENTS = { 'report.created' => 'abuseReport', 'report.updated' => 'abuseReportResolved', 'account.created' => 'userRegistered' }.freeze

  misskey_admin_endpoint 'read:admin:abuse-report:notification-recipient', :index, :show, area: 'reports', secure: true
  misskey_admin_endpoint 'write:admin:abuse-report:notification-recipient', :create, :update, :destroy, area: 'reports', secure: true

  before_action :set_recipient, only: [:show, :update, :destroy]

  def index
    authorize :report, :index?
    methods = params[:method]
    return render_invalid_param('#/properties/method', 'must be an array of allowed values') unless methods.nil? || (methods.is_a?(Array) && methods.all? { |value| MisskeyAbuseReportRecipient::METHODS.include?(value) })

    scope = MisskeyAbuseReportRecipient.includes(:account, :webhook).order(id: :asc)
    scope = scope.where(delivery_method: methods) unless methods.nil?
    render json: scope.map { |recipient| serialize_recipient(recipient) }
  end

  def show
    authorize :report, :index?
    render json: serialize_recipient(@recipient)
  end

  def create
    authorize :report, :update?
    recipient = MisskeyAbuseReportRecipient.new
    return unless assign_recipient(recipient)

    recipient.save!
    render json: serialize_recipient(recipient)
  end

  def update
    authorize :report, :update?
    return unless assign_recipient(@recipient)

    @recipient.save!
    render json: serialize_recipient(@recipient)
  end

  def destroy
    authorize :report, :update?
    @recipient.destroy!
    head 204
  end

  private

  def set_recipient
    @recipient = MisskeyAbuseReportRecipient.find_by(id: MisskeyCompat::MiId.decode(params[:id].to_s))
    render_error('No such recipient', 'NO_SUCH_RECIPIENT', 404, id: '013de6a8-f757-04cb-4d73-cc2a7e3368e4', kind: 'server') if @recipient.nil?
  end

  def assign_recipient(recipient)
    return invalid_recipient_param(:isActive, 'must be boolean') unless [true, false].include?(params[:isActive])
    return invalid_recipient_param(:name, 'must be a string of 1 to 255 characters') unless params[:name].is_a?(String) && params[:name].length.between?(1, 255)
    return invalid_recipient_param(:method, 'must be equal to one of the allowed values') unless MisskeyAbuseReportRecipient::METHODS.include?(params[:method])

    recipient.assign_attributes(active: params[:isActive], name: params[:name], delivery_method: params[:method], account: nil, webhook: nil)
    params[:method] == 'email' ? assign_email_target(recipient) : assign_webhook_target(recipient)
  end

  def assign_email_target(recipient)
    account = params[:userId].present? ? Account.local.find_by(id: params[:userId]) : nil
    if account&.user.nil?
      render_error('If "method" is email, "userId" must be set', 'CORRELATION_CHECK_EMAIL', 400, id: '348bb8ae-575a-6fe9-4327-5811999def8f')
      return false
    end

    if account.user.email.blank? || !account.user.confirmed?
      render_error('Email address is not set', 'EMAIL_ADDRESS_NOT_SET', 400, id: '7cc1d85e-2f58-fc31-b644-3de8d0d3421f')
      return false
    end

    recipient.account = account
    true
  end

  def assign_webhook_target(recipient)
    webhook = params[:systemWebhookId].present? ? Webhook.find_by(id: MisskeyCompat::MiId.decode(params[:systemWebhookId].to_s)) : nil
    if webhook.nil?
      render_error('If "method" is webhook, "systemWebhookId" must be set', 'CORRELATION_CHECK_WEBHOOK', 400, id: 'b0c15051-de2d-29ef-260c-9585cddd701a')
      return false
    end

    authorize webhook, :show?
    recipient.webhook = webhook
    true
  end

  def invalid_recipient_param(key, reason)
    render_invalid_param("#/properties/#{key}", reason)
    false
  end

  def serialize_recipient(recipient)
    {
      id: MisskeyCompat::MiId.encode(recipient.id),
      isActive: recipient.active?,
      updatedAt: recipient.updated_at.iso8601,
      name: recipient.name,
      method: recipient.delivery_method,
      userId: recipient.account_id && MisskeyCompat::MiId.encode(recipient.account_id),
      user: recipient.account && MisskeyCompat::UserSerializer.serialize(recipient.account),
      systemWebhookId: recipient.webhook_id && MisskeyCompat::MiId.encode(recipient.webhook_id),
      systemWebhook: recipient.webhook && serialize_webhook(recipient.webhook),
    }.compact
  end

  def serialize_webhook(webhook)
    {
      id: MisskeyCompat::MiId.encode(webhook.id),
      isActive: webhook.enabled?,
      updatedAt: webhook.updated_at.iso8601,
      latestSentAt: nil,
      latestStatus: nil,
      name: webhook.url,
      on: webhook.events.filter_map { |event| WEBHOOK_EVENTS[event] },
      url: webhook.url,
      secret: WebhookPolicy.new(current_account, webhook).show? ? webhook.secret : '',
    }
  end
end
