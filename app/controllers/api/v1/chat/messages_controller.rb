# frozen_string_literal: true

class Api::V1::Chat::MessagesController < Api::V1::Chat::BaseController
  LIMIT = 40
  SEARCH_QUERY_LIMIT = 200

  before_action :authorize_chat_read!, only: [:index, :show, :search]
  before_action :authorize_chat_write!, only: [:create, :update, :destroy]
  before_action :enforce_chat_write_rate_limit!, only: [:create, :update, :destroy]
  before_action :set_conversation, only: [:index, :create]
  before_action :set_message, only: [:show, :update, :destroy]
  before_action :enforce_search_rate_limit!, only: :search

  def index
    messages = @conversation.messages.visible_to(current_account).includes(account: [:account_stat, :user], reactions: { account: [:account_stat, :user] }, media_attachments: :chat_message_media_attachments).limit(limit_param(LIMIT, 80))
    messages = messages.where(id: ...params[:max_id]) if chat_id_param(:max_id).present?
    messages = messages.to_a.reverse
    ChatMessageReaction.preload_custom_emojis(messages.flat_map(&:reactions))
    render json: messages, each_serializer: REST::ChatMessageSerializer, current_account: current_account
  end

  def show
    render json: @message, serializer: REST::ChatMessageSerializer, current_account: current_account
  end

  def search
    query = params[:q].to_s.strip
    raise Mastodon::InvalidParameterError, 'Search query is required' if query.blank?
    raise Mastodon::InvalidParameterError, 'Search query is too long' if query.length > SEARCH_QUERY_LIMIT

    messages = ChatMessage.visible.visible_to(current_account)
      .joins(chat_conversation: :memberships)
      .where(chat_memberships: { account_id: current_account.id })
      .where('chat_messages.text ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(query)}%")
      .includes(account: [:account_stat, :user], reactions: { account: [:account_stat, :user] }, media_attachments: :chat_message_media_attachments)
      .distinct
      .order(id: :desc)
      .limit(limit_param(LIMIT, 80))
    messages = messages.where(chat_conversation_id: params[:conversation_id]) if params[:conversation_id].present?
    messages = messages.to_a
    ChatMessageReaction.preload_custom_emojis(messages.flat_map(&:reactions))
    render json: messages, each_serializer: REST::ChatMessageSerializer, current_account: current_account
  end

  def create
    message = chat_service.create_message(
      current_account,
      @conversation,
      text: params[:text],
      reply_to_id: params[:reply_to_id],
      media_ids: Array(params[:media_ids])
    )
    render json: message, serializer: REST::ChatMessageSerializer, current_account: current_account
  end

  def update
    message = chat_service.update_message(current_account, @message, text: params[:text])
    render json: message, serializer: REST::ChatMessageSerializer, current_account: current_account
  end

  def destroy
    chat_service.delete_message(current_account, @message)
    render_empty
  end

  private

  def enforce_search_rate_limit!
    RateLimiter.new(current_account, family: :chat_searches).record!
  end

  def set_message
    @message = ChatMessage.visible_to(current_account).joins(chat_conversation: :memberships)
      .where(chat_memberships: { account_id: current_account.id })
      .find(params[:id])
  end
end
