# frozen_string_literal: true

class ActivityPub::ChatRoomsController < ActivityPub::BaseController
  before_action :require_account_signature!

  def show
    response.headers['Cache-Control'] = 'private, no-store'

    conversation = ChatConversation.find_by(id: params[:id])
    return head :not_found if conversation.nil?
    return head :not_found unless visible_to_signed_account?(conversation)

    object = Sharlayan::ChatFederation::Payload.room(conversation)
    object['@context'] = Sharlayan::ChatFederation::Payload::CONTEXT
    render json: object
  end

  private

  def account_required?
    false
  end

  def visible_to_signed_account?(conversation)
    account = signed_request_account

    conversation.owner_account_id == account.id ||
      conversation.memberships.exists?(account: account) ||
      conversation.invitations.pending.exists?(invitee_account: account)
  end
end