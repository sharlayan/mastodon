# frozen_string_literal: true

class ActivityPub::ChatRoomsController < ActivityPub::BaseController
  before_action :require_chat_readable!
  before_action :require_account_signature!

  def show
    response.headers['Cache-Control'] = 'private, no-store'

    conversation = ChatConversation.chat_group.find_by(id: params[:id])
    return head 404 if conversation.nil? || !conversation.local?
    return head 404 unless visible_to_signed_account?(conversation)

    object = Sharlayan::ChatFederation::Payload.room(conversation)
    object['@context'] = Sharlayan::ChatFederation::Payload::CONTEXT
    object.merge!(Sharlayan::ChatFederation::Payload.roster(conversation)) if conversation.memberships.exists?(account: signed_request_account)
    render json: object, content_type: 'application/activity+json'
  end

  private

  def account_required?
    false
  end

  def require_chat_readable!
    head 404 unless Setting.chat_enabled && Setting.chat_federation_enabled
  end

  def visible_to_signed_account?(conversation)
    account = signed_request_account
    return false if account.nil? || account.suspended? || account.unavailable?

    conversation.owner_account_id == account.id ||
      conversation.memberships.exists?(account: account) ||
      conversation.invitations.pending.exists?(invitee_account: account)
  end
end
