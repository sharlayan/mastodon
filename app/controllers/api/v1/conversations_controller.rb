# frozen_string_literal: true

class Api::V1::ConversationsController < Api::BaseController
  LIMIT = 20
  STATUSES_LIMIT = 40

  before_action -> { doorkeeper_authorize! :read, :'read:statuses' }, only: [:index, :statuses]
  before_action -> { doorkeeper_authorize! :write, :'write:conversations' }, only: [:read, :unread, :destroy]
  before_action :require_user!
  before_action :set_conversation, except: :index
  after_action :insert_pagination_headers, only: [:index, :statuses]

  def index
    @conversations = paginated_conversations
    render json: @conversations, each_serializer: REST::ConversationSerializer, relationships: StatusRelationshipsPresenter.new(@conversations.map(&:last_status), current_user&.account_id)
  end

  def statuses
    @statuses = paginated_grouped_statuses
    render json: @statuses, each_serializer: REST::StatusSerializer, relationships: StatusRelationshipsPresenter.new(@statuses, current_user&.account_id)
  end

  def read
    @conversation.update!(unread: false)
    render json: @conversation, serializer: REST::ConversationSerializer
  end

  def unread
    @conversation.update!(unread: true)
    render json: @conversation, serializer: REST::ConversationSerializer
  end

  def destroy
    @conversation.destroy!
    render_empty
  end

  private

  def set_conversation
    @conversation = AccountConversation.where(account: current_account).find(params[:id])
  end

  def grouped?
    params[:grouped].present?
  end

  def paginated_conversations
    scope = AccountConversation.where(account: current_account)
      .includes(
        account: [:account_stat, user: :role],
        last_status: [
          :media_attachments,
          :status_stat,
          :tags,
          {
            preview_cards_status: { preview_card: { author_account: [:account_stat, user: :role] } },
            active_mentions: :account,
            account: [:account_stat, user: :role],
          },
        ]
      )

    return scope.to_a_paginated_by_id(limit_param(LIMIT), params_slice(:max_id, :since_id, :min_id)) unless grouped?

    grouped_conversations(scope)
  end

  def grouped_conversations(scope)
    representatives = AccountConversation
      .select('DISTINCT ON (participant_account_ids) id')
      .where(account: current_account)
      .order(:participant_account_ids, last_status_id: :desc)

    ids = scope.where(id: representatives).to_a_paginated_by_id(limit_param(LIMIT), params_slice(:max_id, :since_id, :min_id))

    annotate_grouped(ids)
  end

  def annotate_grouped(conversations)
    return conversations if conversations.empty?

    grouped = AccountConversation
      .where(account: current_account)
      .pluck(:participant_account_ids, :id, :unread)
      .group_by { |participant_ids, _, _| participant_ids.sort }

    conversations.each do |conversation|
      group = grouped[conversation.participant_account_ids.sort] || []
      conversation.member_ids   = group.map { |_, id, _| id }
      conversation.group_unread = group.any? { |_, _, unread| unread }
    end

    conversations
  end

  def paginated_grouped_statuses
    status_ids = grouped_status_ids

    Status.where(id: status_ids)
      .includes(:media_attachments, :status_stat, :tags, active_mentions: :account, account: [:account_stat, user: :role])
      .to_a_paginated_by_id(limit_param(STATUSES_LIMIT, STATUSES_LIMIT), params_slice(:max_id, :since_id, :min_id))
  end

  def grouped_status_ids
    AccountConversation
      .where(account: current_account, participant_account_ids: @conversation.participant_account_ids)
      .pluck(:status_ids)
      .flatten
      .uniq
  end

  def next_path
    if action_name == 'statuses'
      statuses_api_v1_conversation_url(@conversation, pagination_params(max_id: pagination_max_id)) if records_continue?
    elsif records_continue?
      api_v1_conversations_url pagination_params(max_id: pagination_max_id)
    end
  end

  def prev_path
    return if records_collection.empty?

    if action_name == 'statuses'
      statuses_api_v1_conversation_url(@conversation, pagination_params(min_id: pagination_since_id))
    else
      api_v1_conversations_url pagination_params(min_id: pagination_since_id)
    end
  end

  def records_collection
    @records_collection ||= action_name == 'statuses' ? @statuses : @conversations
  end

  def pagination_max_id
    action_name == 'statuses' ? records_collection.last.id : records_collection.last.last_status_id
  end

  def pagination_since_id
    action_name == 'statuses' ? records_collection.first.id : records_collection.first.last_status_id
  end

  def records_continue?
    records_collection.size == (action_name == 'statuses' ? limit_param(STATUSES_LIMIT, STATUSES_LIMIT) : limit_param(LIMIT))
  end
end
