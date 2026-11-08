# frozen_string_literal: true

class ActivityPub::ChatMessagesController < ActivityPub::BaseController
  before_action :require_chat_readable!
  before_action :require_account_signature!

  def show
    response.headers['Cache-Control'] = 'private, no-store'

    message = ChatMessage.find_by(id: params[:id])
    return head 404 if message.nil? || !message.account.local? || message.account.suspended?

    unless visible_to_signed_account?(message)
      Sharlayan::ChatFederation::Roster.request_sync(message.chat_conversation, signed_request_account.id) if signed_request_account&.suspended? == false
      return head 404
    end

    if message.deleted?
      render_ap(
        '@context' => Sharlayan::ChatFederation::Payload::CONTEXT,
        'id' => Sharlayan::ChatFederation::Payload.message_uri(message),
        'type' => 'Tombstone',
        'formerType' => 'Note'
      )
    else
      render_ap(Sharlayan::ChatFederation::Payload.note(message, domain: signed_request_account.domain))
    end
  end

  private

  def account_required?
    false
  end

  def require_chat_readable!
    head 404 unless Setting.chat_enabled && Sharlayan::ChatFederation.enabled?
  end

  def visible_to_signed_account?(message)
    account = signed_request_account
    return false if account.nil? || account.suspended? || account.unavailable?

    conversation = message.chat_conversation
    conversation.memberships.exists?(account: account)
  end

  def render_ap(object)
    object['@context'] = (Sharlayan::ChatFederation::Payload::CONTEXT + Array(object['@context'])).uniq
    render json: object, content_type: 'application/activity+json'
  end
end
