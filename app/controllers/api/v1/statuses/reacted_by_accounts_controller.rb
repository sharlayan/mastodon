# frozen_string_literal: true

class Api::V1::Statuses::ReactedByAccountsController < Api::V1::Statuses::BaseController
  before_action -> { authorize_if_got_token! :read, :'read:accounts' }
  after_action :insert_pagination_headers, only: [:index]

  def index
    cache_if_unauthenticated!
    @reactions = load_reactions
    render json: @reactions, each_serializer: REST::EmojiReactAccountSerializer
  end

  private

  def load_reactions
    scope = default_reactions
    scope = scope.merge(Account.not_excluded_by_account(current_account)) if current_account.present?
    scope.paginate_by_max_id(
      limit_param(DEFAULT_ACCOUNTS_LIMIT),
      params[:max_id],
      params[:since_id]
    ).to_a
  end

  def default_reactions
    scope = StatusReaction
      .where(status_id: @status.id)
      .joins(:account)
      .merge(Account.without_suspended)
      .includes(:custom_emoji, account: [:account_stat, :user])

    return scope if params[:name].blank?

    name, domain = params[:name].to_s.split('@', 2)
    custom_emoji = CustomEmoji.find_by(shortcode: name, domain: domain)
    scope.where(name: name, custom_emoji: custom_emoji)
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
