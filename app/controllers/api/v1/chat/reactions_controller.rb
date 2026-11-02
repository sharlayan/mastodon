# frozen_string_literal: true

class Api::V1::Chat::ReactionsController < Api::V1::Chat::BaseController
  before_action :authorize_chat_write!
  before_action :enforce_chat_write_rate_limit!
  before_action :set_message

  def create
    reaction = chat_service.react(current_account, @message, params[:reaction])
    render json: reaction, serializer: REST::ChatMessageReactionSerializer
  end

  def destroy
    chat_service.unreact(current_account, @message, params[:reaction])
    render_empty
  end

  private

  def set_message
    @message = ChatMessage.visible_to(current_account).joins(chat_conversation: :memberships)
      .where(chat_memberships: { account_id: current_account.id })
      .find(params[:message_id])
  end
end
