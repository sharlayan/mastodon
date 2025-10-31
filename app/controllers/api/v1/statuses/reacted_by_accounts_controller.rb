# frozen_string_literal: true

class Api::V1::Statuses::ReactedByAccountsController < Api::V1::Statuses::BaseController
  before_action -> { authorize_if_got_token! :read, :'read:accounts' }
  after_action :insert_pagination_headers, only: [:index]

  def index
    cache_if_unauthenticated!
    @accounts = load_accounts
    render json: @accounts, each_serializer: REST::EmojiReactAccountSerializer
  end

  private

  def load_accounts
    scope = default_accounts
    # scope = scope.not_excluded_by_account(current_account) unless current_account.nil?
    scope.merge(paginated_reactions).to_a
  end

  def default_accounts
    Account
      .without_suspended
      .includes(:status_reactions, :account_stat, :user)
      .references(:status_reactions)
      .where(status_reactions: { status_id: @status.id })
  end

  def paginated_status_reactions
    StatusReaction
      .where(status_id: @status.id)
      .paginate_by_max_id(
        limit_param(DEFAULT_ACCOUNTS_LIMIT),
        params[:max_id],
        params[:since_id]
      )
  end

  def insert_pagination_headers
    set_pagination_headers(next_path, prev_path)
  end

  def next_path
    api_v1_status_reacted_by_index_url pagination_params(max_id: pagination_max_id) if records_continue?
  end

  def prev_path
    api_v1_status_reacted_by_index_url pagination_params(since_id: pagination_since_id) unless @reactions.empty?
  end

  def pagination_max_id
    @reactions.last.id
  end

  def pagination_since_id
    @reactions.first.id
  end

  def records_continue?
    @reactions.size == limit_param(DEFAULT_ACCOUNTS_LIMIT)
  end
end
