# frozen_string_literal: true

class MisskeyCompatWebhookEventWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'push'

  STATUS_EVENTS = %w(note reply renote mention).freeze

  def perform(event, account_id, object_type, object_id)
    @owner = Account.find(account_id)
    return unless @owner.local? && @owner.user&.functional?

    webhooks = MisskeyWebhook.active.listening_to(event).where(account: @owner).to_a
    return if webhooks.empty?

    content = build_content(event, object_type, object_id)
    return if content.nil?

    webhooks.each { |webhook| MisskeyCompatWebhookDeliveryWorker.perform_async(webhook.id.to_s, self.class.payload(webhook, event, content)) }
  rescue ActiveRecord::RecordNotFound
    true
  end

  def self.payload(webhook, event, content)
    {
      server: Rails.application.routes.url_helpers.root_url(ActionMailer::Base.default_url_options).chomp('/'),
      hookId: MisskeyCompat::MiId.encode(webhook.id),
      userId: MisskeyCompat::MiId.encode(webhook.account_id),
      eventId: SecureRandom.uuid,
      createdAt: (Time.now.to_f * 1000).to_i,
      type: event,
      body: content,
    }.to_json
  end

  private

  def build_content(event, object_type, object_id)
    if STATUS_EVENTS.include?(event)
      return unless object_type == 'Status'

      status_content(event, Status.find(object_id))
    elsif object_type == 'Account'
      account_content(event, Account.find(object_id))
    end
  end

  def status_content(event, status)
    return unless event == 'note' || StatusPolicy.new(@owner, status).show?
    return if event.in?(%w(reply mention)) && status.conversation && @owner.muting_conversation?(status.conversation)

    context = MisskeyCompat::SerializationContext.for([status], current_account: @owner)
    { note: MisskeyCompat::NoteSerializer.serialize(status, context: context) }
  end

  def account_content(event, account)
    user = if event == 'followed'
             MisskeyCompat::UserSerializer.serialize(account)
           else
             MisskeyCompat::UserSerializer.serialize(account, detailed: true, viewer: @owner)
           end
    { user: user }
  end
end
