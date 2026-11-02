# frozen_string_literal: true

class Api::V1::Chat::ConversationsController < Api::V1::Chat::BaseController
  LIMIT = 20

  before_action :authorize_chat_read!, only: [:index, :show]
  before_action :authorize_chat_write!, except: [:index, :show]
  before_action :enforce_chat_write_rate_limit!, except: [:index, :show]
  before_action :set_conversation, only: [:show, :update, :destroy, :read, :leave, :mute, :unmute, :archive, :unarchive]

  def index
    conversations = ChatConversation.for_account(current_account)
      .includes(:accounts, :memberships, last_message: [:account, reactions: :account])
      .order(Arel.sql('chat_conversations.last_message_id DESC NULLS LAST, chat_conversations.id DESC'))
      .limit(limit_param(LIMIT, 40))
    if params[:max_id].present?
      cursor = ChatConversation.for_account(current_account).find(params[:max_id])
      conversations = if cursor.last_message_id.nil?
                        conversations.where(last_message_id: nil).where(id: ...cursor.id)
                      else
                        conversations.where(
                          'chat_conversations.last_message_id < :message_id OR (chat_conversations.last_message_id = :message_id AND chat_conversations.id < :id) OR chat_conversations.last_message_id IS NULL',
                          message_id: cursor.last_message_id, id: cursor.id
                        )
                      end
    end
    render json: conversations, each_serializer: REST::ChatConversationSerializer, current_account: current_account
  end

  def show
    render json: @conversation, serializer: REST::ChatConversationSerializer, current_account: current_account
  end

  def create
    conversation = chat_service.create_conversation(
      current_account,
      type: params[:type],
      account_ids: Array(params[:account_ids]),
      title: params[:title],
      description: params[:description]
    )
    render json: conversation, serializer: REST::ChatConversationSerializer, current_account: current_account
  end

  def update
    conversation = chat_service.update_conversation(current_account, @conversation, params.permit(:title, :description))
    render json: conversation, serializer: REST::ChatConversationSerializer, current_account: current_account
  end

  def destroy
    chat_service.destroy_conversation(current_account, @conversation)
    render_empty
  end

  def read
    membership = chat_service.mark_read(current_account, @conversation, message_id: params[:message_id])
    render json: { conversation_id: @conversation.id.to_s, last_read_message_id: membership.last_read_message_id&.to_s }
  end

  def leave
    chat_service.leave(current_account, @conversation)
    render_empty
  end

  def mute
    chat_service.mute(current_account, @conversation, muted: true)
    render_empty
  end

  def unmute
    chat_service.mute(current_account, @conversation, muted: false)
    render_empty
  end

  def archive
    render json: chat_service.archive(current_account, @conversation, archived: true), serializer: REST::ChatConversationSerializer, current_account: current_account
  end

  def unarchive
    render json: chat_service.archive(current_account, @conversation, archived: false), serializer: REST::ChatConversationSerializer, current_account: current_account
  end
end
