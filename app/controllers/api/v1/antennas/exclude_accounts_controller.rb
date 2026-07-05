# frozen_string_literal: true

class Api::V1::Antennas::ExcludeAccountsController < Api::BaseController
  before_action -> { doorkeeper_authorize! :read, :'read:lists' }, only: [:show]
  before_action -> { doorkeeper_authorize! :write, :'write:lists' }, except: [:show]

  before_action :require_user!
  before_action :set_antenna

  def show
    render json: load_accounts, each_serializer: REST::AccountSerializer
  end

  def create
    ids = (@antenna.exclude_accounts + account_ids).uniq
    raise Mastodon::ValidationError, I18n.t('antennas.errors.too_many_accounts') if ids.size > Antenna::ACCOUNTS_PER_ANTENNA_LIMIT

    @antenna.update!(exclude_accounts: ids)
    render json: load_accounts, each_serializer: REST::AccountSerializer
  end

  def destroy
    @antenna.update!(exclude_accounts: @antenna.exclude_accounts - account_ids)
    render json: load_accounts, each_serializer: REST::AccountSerializer
  end

  private

  def set_antenna
    @antenna = Antenna.where(account: current_account).find(params[:antenna_id])
  end

  def load_accounts
    Account.where(id: @antenna.exclude_accounts).without_suspended.includes(:account_stat, :user)
  end

  def account_ids
    Array(params.permit(account_ids: [])[:account_ids]).map(&:to_s)
  end
end
