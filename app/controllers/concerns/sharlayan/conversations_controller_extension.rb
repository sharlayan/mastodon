# frozen_string_literal: true

module Sharlayan::ConversationsControllerExtension
  STATUSES_LIMIT = 50
  STATUSES_DEFAULT_LIMIT = 50
  PRESERVED_GROUPS_SQL = <<~SQL.squish.freeze
    WITH rows AS MATERIALIZED (
      SELECT id, conversation_id, participant_account_ids, last_status_id, unread
      FROM account_conversations
      WHERE account_id = :account_id
    ), leaves AS (
      SELECT candidate.*
      FROM rows candidate
      WHERE NOT EXISTS (
        SELECT 1
        FROM rows superset
        WHERE superset.conversation_id = candidate.conversation_id
          AND candidate.participant_account_ids <@ superset.participant_account_ids
          AND candidate.participant_account_ids <> superset.participant_account_ids
      )
    ), expanded AS (
      SELECT TRUE AS expanded,
             leaf.id AS representative_id,
             (ARRAY_AGG(member.id ORDER BY member.last_status_id DESC, member.id DESC))[1] AS latest_id,
             MAX(member.last_status_id) AS last_status_id,
             ARRAY_AGG(member.id ORDER BY member.id) AS member_ids,
             BOOL_OR(member.unread) AS unread
      FROM leaves leaf
      INNER JOIN rows member
        ON member.conversation_id = leaf.conversation_id
       AND member.participant_account_ids <@ leaf.participant_account_ids
      GROUP BY leaf.id
      HAVING COUNT(*) > 1
    ), consumed AS (
      SELECT DISTINCT UNNEST(member_ids) AS id
      FROM expanded
    ), grouped AS (
      SELECT FALSE AS expanded,
             (ARRAY_AGG(row.id ORDER BY row.last_status_id DESC, row.id DESC))[1] AS representative_id,
             (ARRAY_AGG(row.id ORDER BY row.last_status_id DESC, row.id DESC))[1] AS latest_id,
             MAX(row.last_status_id) AS last_status_id,
             ARRAY_AGG(row.id ORDER BY row.id) AS member_ids,
             BOOL_OR(row.unread) AS unread
      FROM rows row
      WHERE NOT EXISTS (SELECT 1 FROM consumed WHERE consumed.id = row.id)
      GROUP BY row.participant_account_ids
    )
    SELECT expanded, representative_id, latest_id, last_status_id, member_ids, unread
    FROM (
      SELECT * FROM expanded
      UNION ALL
      SELECT * FROM grouped
    ) definitions
  SQL

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
    members = group_members
    AccountConversation.where(id: members.map(&:id)).update_all(unread: unread)
    MarkStatusesReadService.new.call(current_account, members.flat_map(&:status_ids)) unless unread
    @conversation.reload
    render json: @conversation, serializer: REST::ConversationSerializer
  end

  def group_members
    return preserved_group_members(@conversation) if preserve_group?

    AccountConversation.where(account: current_account, participant_account_ids: @conversation.participant_account_ids).to_a
  end

  def paginated_grouped_statuses
    Status.where(id: grouped_status_ids).includes(:media_attachments, :status_read_receipts, :status_stat, :tags, active_mentions: :account, account: [:account_stat, user: :role]).to_a_paginated_by_id(statuses_limit, params_slice(:max_id, :since_id, :min_id))
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
    limit = limit_param(Api::V1::ConversationsController::LIMIT)
    definitions = preserved_group_definitions(limit: limit, max_id: params[:max_id], since_id: params[:since_id], min_id: params[:min_id])

    row_ids = definitions.flat_map { |definition| [definition[:representative_id], definition[:latest_id]] }.uniq
    conversations = paginated_conversations_scope.where(id: row_ids).index_by(&:id)
    definitions.filter_map { |definition| annotate_preserved_group(definition, conversations) }
  end

  def preserved_group_members(conversation)
    definition = preserved_group_definition_for(conversation.id)
    definition ? AccountConversation.where(account: current_account, id: definition[:member_ids]).to_a : [conversation]
  end

  def preserved_group_definitions(limit:, max_id: nil, since_id: nil, min_id: nil)
    conditions = []
    conditions << 'last_status_id < :max_id' if max_id.present?
    conditions << 'last_status_id > :since_id' if since_id.present?
    conditions << 'last_status_id > :min_id' if min_id.present?
    order = min_id.present? ? 'last_status_id ASC' : 'last_status_id DESC'
    sql = <<~SQL.squish
      #{PRESERVED_GROUPS_SQL}
      #{"WHERE #{conditions.join(' AND ')}" if conditions.any?}
      ORDER BY #{order}, representative_id DESC
      LIMIT :limit
    SQL
    query_preserved_group_definitions(sql, limit: limit, max_id: max_id, since_id: since_id, min_id: min_id).then { |definitions| min_id.present? ? definitions.reverse : definitions }
  end

  def preserved_group_definition_for(conversation_id)
    sql = <<~SQL.squish
      #{PRESERVED_GROUPS_SQL}
      WHERE representative_id = :conversation_id
         OR (NOT expanded AND :conversation_id = ANY(member_ids))
      ORDER BY (representative_id = :conversation_id) DESC
      LIMIT 1
    SQL
    query_preserved_group_definitions(sql, conversation_id: conversation_id).first
  end

  def query_preserved_group_definitions(sql, binds)
    sanitized = AccountConversation.sanitize_sql_array([sql, { account_id: current_account.id, **binds.compact }])
    AccountConversation.connection.select_all(sanitized).map do |row|
      {
        expanded: row.fetch('expanded'),
        representative_id: row.fetch('representative_id').to_i,
        latest_id: row.fetch('latest_id').to_i,
        last_status_id: row.fetch('last_status_id').to_i,
        member_ids: AccountConversation.type_for_attribute('participant_account_ids').deserialize(row.fetch('member_ids')),
        unread: row.fetch('unread'),
      }
    end
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
