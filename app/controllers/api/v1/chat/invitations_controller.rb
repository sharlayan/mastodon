# frozen_string_literal: true

class Api::V1::Chat::InvitationsController < Api::V1::Chat::BaseController
  LIMIT = 40

  before_action :authorize_chat_read!, only: :index
  before_action :authorize_chat_write!, except: :index
  before_action :enforce_chat_write_rate_limit!, except: :index
  before_action :set_invitation, only: [:accept, :reject, :destroy]

  def index
    invitations = ChatInvitation.pending.includes(:chat_conversation, :inviter_account, :invitee_account)
    invitations = params[:direction] == 'sent' ? invitations.where(inviter_account: current_account) : invitations.where(invitee_account: current_account).from_available_inviters
    invitations = invitations.where(id: ...params[:max_id]) if params[:max_id].present?
    invitations = invitations.order(id: :desc).limit(limit_param(LIMIT, LIMIT))
    render json: invitations, each_serializer: REST::ChatInvitationSerializer, current_account: current_account
  end

  def create
    conversation = ChatConversation.for_account(current_account).find(params[:conversation_id])
    invitee = Account.find(params[:account_id])
    invitation = chat_service.invite(current_account, conversation, invitee)
    render json: invitation, serializer: REST::ChatInvitationSerializer, current_account: current_account
  end

  def accept
    conversation = chat_service.accept_invitation(current_account, @invitation)
    render json: conversation, serializer: REST::ChatConversationSerializer, current_account: current_account
  end

  def reject
    chat_service.reject_invitation(current_account, @invitation)
    render_empty
  end

  def destroy
    chat_service.cancel_invitation(current_account, @invitation)
    render_empty
  end

  private

  def set_invitation
    @invitation = ChatInvitation
      .where(inviter_account: current_account)
      .or(ChatInvitation.where(invitee_account: current_account))
      .find(params[:id])
  end
end
