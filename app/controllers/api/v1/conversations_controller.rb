# frozen_string_literal: true

class Api::V1::ConversationsController < Api::BaseController
  LIMIT = 20
  STATUSES_LIMIT = 50
  STATUSES_DEFAULT_LIMIT = 50

  before_action -> { doorkeeper_authorize! :read, :'read:statuses' }, only: [:index, :statuses, :with_account]
  before_action -> { doorkeeper_authorize! :write, :'write:conversations' }, only: [:read, :unread, :destroy]
  before_action :require_user!
  before_action :set_conversation, except: [:index, :with_account]
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
    mark_group_unread(false)
  end

  def unread
    mark_group_unread(true)
  end

  def destroy
    @conversation.destroy!
    render_empty
  end

  def with_account
    id = AccountConversation
      .where(account: current_account, participant_account_ids: [params[:account_id].to_i])
      .order(last_status_id: :desc)
      .pick(:id)

    render json: { id: id&.to_s }
  end

  private

  def set_conversation
    @conversation = AccountConversation.where(account: current_account).find(params[:id])
  end

  def mark_group_unread(unread)
    AccountConversation
      .where(account: current_account, participant_account_ids: @conversation.participant_account_ids)
      .update_all(unread: unread)

    @conversation.reload
    render json: @conversation, serializer: REST::ConversationSerializer
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
      .to_a_paginated_by_id(statuses_limit, params_slice(:max_id, :since_id, :min_id))
  end

  def grouped_status_ids
    inner = AccountConversation
      .where(account: current_account, participant_account_ids: @conversation.participant_account_ids)
      .select(Arel.sql('DISTINCT unnest(status_ids) AS id'))

    scope = Status.unscoped.from(Arel.sql("(#{inner.to_sql}) AS conversation_statuses"))

    max_id   = params[:max_id].presence&.to_i
    since_id = params[:since_id].presence&.to_i
    min_id   = params[:min_id].presence&.to_i

    scope = scope.where(conversation_statuses: { id: ...max_id }) if max_id
    scope = scope.where('conversation_statuses.id > ?', since_id) if since_id
    scope = scope.where('conversation_statuses.id > ?', min_id) if min_id

    direction = min_id ? 'ASC' : 'DESC'

    scope
      .order(Arel.sql("conversation_statuses.id #{direction}"))
      .limit(statuses_limit)
      .pluck(Arel.sql('conversation_statuses.id'))
  end

  def statuses_limit
    limit_param(STATUSES_DEFAULT_LIMIT, STATUSES_LIMIT)
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
    records_collection.size == (action_name == 'statuses' ? statuses_limit : limit_param(LIMIT))
  end
end
