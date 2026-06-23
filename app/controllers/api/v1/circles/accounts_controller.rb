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
    ApplicationRecord.transaction do
      Account.where(id: account_ids).find_each do |account|
        @circle.circle_accounts.create!(account: account)
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
    if unlimited?
      @circle.accounts.without_suspended.includes(:account_stat, :user).all
    else
      @circle.accounts.without_suspended.includes(:account_stat, :user).paginate_by_max_id(limit_param(DEFAULT_ACCOUNTS_LIMIT), params[:max_id], params[:since_id])
    end
  end

  def account_ids
    Array(resource_params[:account_ids])
  end

  def resource_params
    params.permit(account_ids: [])
  end

  def next_path
    return if unlimited?

    api_v1_circle_accounts_url pagination_params(max_id: pagination_max_id) if records_continue?
  end

  def prev_path
    return if unlimited?

    api_v1_circle_accounts_url pagination_params(since_id: pagination_since_id) unless @accounts.empty?
  end

  def pagination_collection
    @accounts
  end

  def records_continue?
    @accounts.size == limit_param(DEFAULT_ACCOUNTS_LIMIT)
  end

  def unlimited?
    params[:limit] == '0'
  end
end
