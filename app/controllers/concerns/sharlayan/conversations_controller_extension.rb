# frozen_string_literal: true

module Sharlayan::ConversationsControllerExtension
  STATUSES_LIMIT = 50
  STATUSES_DEFAULT_LIMIT = 50

  def self.prepended(base)
    base.before_action -> { doorkeeper_authorize! :read, :'read:statuses' }, only: [:statuses, :with_account]
    base.skip_before_action :set_conversation, only: :with_account
  end

  def index
    return super unless grouped?

    @conversations = grouped_conversations
    render json: @conversations, each_serializer: REST::ConversationSerializer, relationships: StatusRelationshipsPresenter.new(@conversations.map(&:last_status), current_user&.account_id)
  end

  def read
    mark_group_unread(false)
  end

  def unread
    mark_group_unread(true)
  end

  def statuses
    @statuses = paginated_grouped_statuses
    render json: @statuses, each_serializer: REST::StatusSerializer, relationships: StatusRelationshipsPresenter.new(@statuses, current_user&.account_id)
  end

  def with_account
    id = AccountConversation.where(account: current_account, participant_account_ids: [params[:account_id].to_i]).order(last_status_id: :desc).pick(:id)

    render json: { id: id&.to_s }
  end

  private

  def grouped?
    params[:grouped].present?
  end

  def grouped_conversations
    scope = paginated_conversations_scope
    representatives = AccountConversation.select('DISTINCT ON (participant_account_ids) id').where(account: current_account).order(:participant_account_ids, last_status_id: :desc)
    conversations = scope.where(id: representatives).to_a_paginated_by_id(limit_param(Api::V1::ConversationsController::LIMIT), params_slice(:max_id, :since_id, :min_id))
    annotate_grouped(conversations)
  end

  def paginated_conversations_scope
    AccountConversation.where(account: current_account).includes(
      account: [:account_stat, user: :role],
      last_status: [:media_attachments, :status_stat, :tags, { preview_cards_status: { preview_card: { author_account: [:account_stat, user: :role] } }, active_mentions: :account, account: [:account_stat, user: :role] }]
    )
  end

  def annotate_grouped(conversations)
    return conversations if conversations.empty?

    grouped = AccountConversation.where(account: current_account).pluck(:participant_account_ids, :id, :unread).group_by { |participant_ids, _, _| participant_ids.sort }
    conversations.each do |conversation|
      group = grouped[conversation.participant_account_ids.sort] || []
      conversation.member_ids = group.map { |_, id, _| id }
      conversation.group_unread = group.any? { |_, _, unread| unread }
    end
    conversations
  end

  def mark_group_unread(unread)
    AccountConversation.where(account: current_account, participant_account_ids: @conversation.participant_account_ids).update_all(unread: unread)
    @conversation.reload
    render json: @conversation, serializer: REST::ConversationSerializer
  end

  def paginated_grouped_statuses
    Status.where(id: grouped_status_ids).includes(:media_attachments, :status_stat, :tags, active_mentions: :account, account: [:account_stat, user: :role]).to_a_paginated_by_id(statuses_limit, params_slice(:max_id, :since_id, :min_id))
  end

  def grouped_status_ids
    inner = AccountConversation.where(account: current_account, participant_account_ids: @conversation.participant_account_ids).select(Arel.sql('DISTINCT unnest(status_ids) AS id'))
    scope = Status.unscoped.from(Arel.sql("(#{inner.to_sql}) AS conversation_statuses"))
    max_id = params[:max_id].presence&.to_i
    since_id = params[:since_id].presence&.to_i
    min_id = params[:min_id].presence&.to_i
    scope = scope.where(conversation_statuses: { id: ...max_id }) if max_id
    scope = scope.where('conversation_statuses.id > ?', since_id) if since_id
    scope = scope.where('conversation_statuses.id > ?', min_id) if min_id
    scope.order(Arel.sql("conversation_statuses.id #{min_id ? 'ASC' : 'DESC'}")).limit(statuses_limit).pluck(Arel.sql('conversation_statuses.id'))
  end

  def statuses_limit
    limit_param(STATUSES_DEFAULT_LIMIT, STATUSES_LIMIT)
  end

  def next_path
    return statuses_api_v1_conversation_url(@conversation, pagination_params(max_id: pagination_max_id)) if action_name == 'statuses' && records_continue?

    super
  end

  def prev_path
    return super unless action_name == 'statuses'
    return if @statuses.empty?

    statuses_api_v1_conversation_url(@conversation, pagination_params(min_id: pagination_since_id))
  end

  def pagination_max_id
    return @statuses.last.id if action_name == 'statuses'

    super
  end

  def pagination_since_id
    return @statuses.first.id if action_name == 'statuses'

    super
  end

  def records_continue?
    return @statuses.size == statuses_limit if action_name == 'statuses'

    super
  end
end
