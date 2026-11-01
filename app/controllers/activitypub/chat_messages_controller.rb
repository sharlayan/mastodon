# frozen_string_literal: true

class ActivityPub::ChatMessagesController < ActivityPub::BaseController
  before_action :require_account_signature!

  def show
    response.headers['Cache-Control'] = 'private, no-store'

    message = ChatMessage.find_by(id: params[:id])
    return head :not_found if message.nil?
    return head :not_found unless visible_to_signed_account?(message)

    if message.deleted?
      render_ap(
        '@context' => Sharlayan::ChatFederation::Payload::CONTEXT,
        'id' => Sharlayan::ChatFederation::Payload.message_uri(message),
        'type' => 'Tombstone',
        'formerType' => 'Note'
      )
    else
      render_ap(Sharlayan::ChatFederation::Payload.note(message))
    end
  end

  private

  def account_required?
    false
  end

  def visible_to_signed_account?(message)
    conversation = message.chat_conversation
    conversation.memberships.exists?(account: signed_request_account)
  end

  def render_ap(object)
    context = object.delete('@context')
    object['@context'] = [Sharlayan::ChatFederation::Payload::CONTEXT, context].compact
    render json: object
  end
end