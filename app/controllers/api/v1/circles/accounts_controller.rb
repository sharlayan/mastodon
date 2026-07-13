# frozen_string_literal: true

class Api::V1::Circles::AccountsController < Api::BaseController
  before_action :require_feature_enabled!
  before_action -> { doorkeeper_authorize! :read, :'read:lists' }, only: [:show]
  before_action -> { doorkeeper_authorize! :write, :'write:lists' }, except: [:show]

  before_action :require_user!
  before_action :set_circle

  after_action :insert_pagination_headers, only: :show

  def show
    @accounts = load_accounts
    render json: @accounts, each_serializer: REST::AccountSerializer
  end

  def create
    ids = account_ids
    raise Mastodon::ValidationError, I18n.t('circles.errors.too_many_accounts') if ids.size > Circle::ACCOUNTS_PER_REQUEST_LIMIT

    accounts = Account.where(id: ids).to_a

    @circle.with_lock do
      existing_ids = @circle.circle_accounts.pluck(:account_id)
      raise Mastodon::ValidationError, I18n.t('circles.errors.too_many_accounts') if (existing_ids | accounts.map(&:id)).size > Circle::ACCOUNTS_PER_CIRCLE_LIMIT

      accounts.each do |account|
        @circle.circle_accounts.create_or_find_by!(account: account)
      end
    end

    render_empty
  end

  def destroy
    CircleAccount.where(circle: @circle, account_id: account_ids).destroy_all
    render_empty
  end

  private

  def require_feature_enabled!
    not_found unless Setting.circles_enabled
  end

  def set_circle
    @circle = Circle.where(account: current_account).find(params[:circle_id])
  end

  def load_accounts
    @circle.accounts.without_suspended.includes(:account_stat, :user).paginate_by_max_id(
      accounts_limit,
      params[:max_id],
      params[:since_id]
    )
  end

  def account_ids
    Array(resource_params[:account_ids]).filter_map { |id| Integer(id, exception: false) }.uniq
  end

  def resource_params
    params.permit(account_ids: [])
  end

  def next_path
    api_v1_circle_accounts_url pagination_params(max_id: pagination_max_id) if records_continue?
  end

  def prev_path
    api_v1_circle_accounts_url pagination_params(since_id: pagination_since_id) unless @accounts.empty?
  end

  def pagination_collection
    @accounts
  end

  def records_continue?
    @accounts.size == accounts_limit
  end

  def accounts_limit
    params[:limit] == '0' ? Circle::ACCOUNTS_PER_REQUEST_LIMIT : limit_param(DEFAULT_ACCOUNTS_LIMIT, Circle::ACCOUNTS_PER_REQUEST_LIMIT)
  end
end
