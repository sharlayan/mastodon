# frozen_string_literal: true

module Sharlayan::ConversationsControllerExtension
  STATUSES_LIMIT = 50
  STATUSES_DEFAULT_LIMIT = 50

  def self.prepended(base)
    base.before_action -> { doorkeeper_authorize! :read, :'read:statuses' }, only: [:statuses, :with_account, :with_status]
    base.skip_before_action :set_conversation, only: [:with_account, :with_status]
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

  def with_status
    status = Status.find_by(id: params[:status_id])
    id = nil

    id = AccountConversation.where(account: current_account, conversation_id: status.conversation_id).order(last_status_id: :desc).pick(:id) if status&.conversation_id

    render json: { id: id&.to_s }
  end

  private

  def grouped?
    params[:grouped].present?
  end

  def grouped_conversations
    return preserved_group_conversations if preserve_group?

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
    ids = preserve_group? ? preserved_group_members(@conversation).map(&:id) : AccountConversation.where(account: current_account, participant_account_ids: @conversation.participant_account_ids).pluck(:id)
    AccountConversation.where(id: ids).update_all(unread: unread)
    @conversation.reload
    render json: @conversation, serializer: REST::ConversationSerializer
  end

  def paginated_grouped_statuses
    Status.where(id: grouped_status_ids).includes(:media_attachments, :status_stat, :tags, active_mentions: :account, account: [:account_stat, user: :role]).to_a_paginated_by_id(statuses_limit, params_slice(:max_id, :since_id, :min_id))
  end

  def grouped_status_ids
    members = if preserve_group?
                AccountConversation.where(id: preserved_group_members(@conversation).map(&:id))
              else
                AccountConversation.where(account: current_account, participant_account_ids: @conversation.participant_account_ids)
              end
    inner = members.select(Arel.sql('DISTINCT unnest(status_ids) AS id'))
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

  def preserve_group?
    ActiveModel::Type::Boolean.new.cast(params[:preserve_group])
  end

  def preserved_group_conversations
    definitions = preserved_group_definitions.sort_by { |definition| -definition[:last_status_id] }

    max_id = params[:max_id].presence&.to_i
    since_id = params[:since_id].presence&.to_i
    min_id = params[:min_id].presence&.to_i
    definitions.select! { |definition| definition[:last_status_id] < max_id } if max_id
    definitions.select! { |definition| definition[:last_status_id] > since_id } if since_id
    definitions.select! { |definition| definition[:last_status_id] > min_id } if min_id
    limit = limit_param(Api::V1::ConversationsController::LIMIT)
    definitions = min_id ? definitions.last(limit) : definitions.first(limit)

    row_ids = definitions.flat_map { |definition| [definition[:representative_id], definition[:latest_id]] }.uniq
    conversations = paginated_conversations_scope.where(id: row_ids).index_by(&:id)
    definitions.filter_map { |definition| annotate_preserved_group(definition, conversations) }
  end

  def preserved_group_members(conversation)
    definitions = preserved_group_definitions
    definition = definitions.find { |candidate| candidate[:representative_id] == conversation.id }
    definition ||= definitions.find { |candidate| !candidate[:expanded] && candidate[:member_ids].include?(conversation.id) }
    definition ? AccountConversation.where(account: current_account, id: definition[:member_ids]).to_a : [conversation]
  end

  def preserved_group_definitions
    rows = AccountConversation.where(account: current_account).select(:id, :conversation_id, :participant_account_ids, :last_status_id, :unread).to_a
    expanded = []
    consumed_ids = Set.new

    rows.group_by(&:conversation_id).each_value do |thread_rows|
      leaves = thread_rows.reject do |candidate|
        thread_rows.any? { |other| proper_participant_subset?(candidate.participant_account_ids, other.participant_account_ids) }
      end

      leaves.each do |leaf|
        members = thread_rows.select { |candidate| participant_subset?(candidate.participant_account_ids, leaf.participant_account_ids) }
        next unless members.any? { |candidate| candidate.participant_account_ids != leaf.participant_account_ids }

        expanded << preserved_group_definition(leaf, members, expanded: true)
        consumed_ids.merge(members.map(&:id))
      end
    end

    grouped = rows.reject { |row| consumed_ids.include?(row.id) }.group_by { |row| row.participant_account_ids.sort }.values.map do |members|
      representative = members.max_by(&:last_status_id)
      preserved_group_definition(representative, members, expanded: false)
    end

    expanded + grouped
  end

  def preserved_group_definition(representative, members, expanded:)
    latest = members.max_by(&:last_status_id)
    {
      expanded: expanded,
      representative_id: representative.id,
      latest_id: latest.id,
      last_status_id: latest.last_status_id,
      member_ids: members.map(&:id),
      unread: members.any?(&:unread),
    }
  end

  def annotate_preserved_group(definition, conversations)
    representative = conversations[definition[:representative_id]]
    latest = conversations[definition[:latest_id]]
    return if representative.nil? || latest.nil?

    representative.last_status = latest.last_status
    representative.last_status_id = definition[:last_status_id]
    representative.member_ids = definition[:expanded] ? [representative.id] : definition[:member_ids]
    representative.group_unread = definition[:unread]
    representative
  end

  def participant_subset?(left, right)
    (left - right).empty?
  end

  def proper_participant_subset?(left, right)
    left != right && participant_subset?(left, right)
  end

  def next_path
    return statuses_api_v1_conversation_url(@conversation, pagination_params(max_id: pagination_max_id).merge(preserve_group: params[:preserve_group])) if action_name == 'statuses' && records_continue?
    return api_v1_conversations_url(pagination_params(max_id: pagination_max_id).merge(grouped: '1', preserve_group: params[:preserve_group])) if action_name == 'index' && preserve_group? && records_continue?

    super
  end

  def prev_path
    return api_v1_conversations_url(pagination_params(min_id: pagination_since_id).merge(grouped: '1', preserve_group: params[:preserve_group])) if action_name == 'index' && preserve_group? && !@conversations.empty?
    return super unless action_name == 'statuses'
    return if @statuses.empty?

    statuses_api_v1_conversation_url(@conversation, pagination_params(min_id: pagination_since_id).merge(preserve_group: params[:preserve_group]))
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
