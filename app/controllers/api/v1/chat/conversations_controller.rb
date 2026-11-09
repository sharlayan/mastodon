# frozen_string_literal: true

class Api::V1::Chat::ConversationsController < Api::V1::Chat::BaseController
  LIMIT = 20

  before_action :authorize_chat_read!, only: [:index, :show]
  before_action :authorize_chat_write!, except: [:index, :show]
  before_action :enforce_chat_write_rate_limit!, except: [:index, :show, :read]
  before_action :set_conversation_or_explain_ending, only: :show
  before_action :set_conversation, only: [:update, :destroy, :read, :leave, :kick, :mute, :unmute, :archive, :unarchive]

  def index
    conversations = ChatConversation.for_account(current_account)
      .preload(:owner_account, :memberships, accounts: [:account_stat, :user], invitations: :invitee_account, last_message: [:account, { reactions: :account, media_attachments: :chat_message_media_attachments }])
      .order(Arel.sql('chat_conversations.last_message_id DESC NULLS LAST, chat_conversations.id DESC'))
      .limit(limit_param(LIMIT, 40))
    if params.key?(:max_id_message_id)
      room_id = snapshot_cursor_part(params[:max_id], allow_zero: false)
      message_id = snapshot_cursor_part(params[:max_id_message_id], allow_zero: true)
      conversations = before_cursor(conversations, room_id, message_id.zero? ? nil : message_id)
    elsif chat_id_param(:max_id).present?
      cursor = ChatConversation.for_account(current_account).find(params[:max_id])
      conversations = before_cursor(conversations, cursor.id, cursor.last_message_id)
    end
    conversations = conversations.to_a
    ChatMessageReaction.preload_custom_emojis(conversations.filter_map(&:last_message).flat_map(&:reactions))
    response.set_header('X-Chat-Cursor-Message-Id', conversations.last.last_message_id&.to_s || '0') if conversations.any?
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
    membership = chat_service.mark_read(current_account, @conversation, message_id: chat_id_param(:message_id))
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

  def kick
    chat_service.kick(current_account, @conversation, Account.find(params[:account_id]))
    render json: @conversation.reload, serializer: REST::ChatConversationSerializer, current_account: current_account
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

  private

  def snapshot_cursor_part(value, allow_zero:)
    raise Mastodon::InvalidParameterError, 'Invalid conversation cursor' unless value.is_a?(String) && value.match?(/\A\d{1,19}\z/)

    number = value.to_i
    raise Mastodon::InvalidParameterError, 'Invalid conversation cursor' if number > 9_223_372_036_854_775_807 || (!allow_zero && number.zero?)

    number
  end

  def before_cursor(conversations, room_id, message_id)
    if message_id.nil?
      conversations.where(last_message_id: nil).where(id: ...room_id)
    else
      conversations.where(
        'chat_conversations.last_message_id < :message_id OR (chat_conversations.last_message_id = :message_id AND chat_conversations.id < :id) OR chat_conversations.last_message_id IS NULL',
        message_id: message_id, id: room_id
      )
    end
  end

  def set_conversation_or_explain_ending
    set_conversation
  rescue ActiveRecord::RecordNotFound
    reason = chat_service.room_ending(current_account, params[:id])
    raise if reason.nil?

    render json: { error: 'Record not found', reason: reason }, status: 404
  end
end
