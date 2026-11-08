# frozen_string_literal: true

class Api::V1::Chat::BaseController < Api::BaseController
  before_action :require_chat_enabled!

  rescue_from Sharlayan::ChatService::Error, with: :render_chat_error
  rescue_from Sharlayan::ChatService::Forbidden, with: :render_chat_forbidden

  private

  def chat_service
    @chat_service ||= Sharlayan::ChatService.new
  end

  def authorize_chat_read!
    doorkeeper_authorize! :read, :'read:statuses'
    require_user! unless performed?
  end

  def authorize_chat_write!
    doorkeeper_authorize! :write, :'write:statuses'
    require_user! unless performed?
  end

  def enforce_chat_write_rate_limit!
    return if Setting.rate_limit_bypass_enabled && current_user.can_extra?(:bypass_rate_limit)

    RateLimiter.new(current_account, family: :chat_writes).record!
  end

  def require_chat_enabled!
    not_found unless Setting.chat_enabled
  end

  def set_conversation
    @conversation = ChatConversation.for_account(current_account).find(params[:conversation_id] || params[:id])
  end

  def render_chat_forbidden
    render json: { error: 'You are not allowed to access this chat' }, status: 403
  end

  def render_chat_error(error)
    render json: { error: error.message }, status: 422
  end
end
