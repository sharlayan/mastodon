# frozen_string_literal: true

class Api::V1::Antennas::AccountsController < Api::BaseController
  include Api::AntennaFeatureConcern

  before_action -> { doorkeeper_authorize! :read, :'read:lists' }, only: [:show]
  before_action -> { doorkeeper_authorize! :write, :'write:lists' }, except: [:show]

  before_action :require_user!
  before_action :set_antenna

  def show
    @accounts = load_accounts
    render json: @accounts, each_serializer: REST::AccountSerializer
  end

  def create
    ApplicationRecord.transaction do
      account_ids.each do |account_id|
        @antenna.antenna_accounts.create_or_find_by!(account_id: account_id) do |antenna_account|
          antenna_account.exclude = false
        end
      end
    end

    validate_limit!
    render_empty
  end

  def destroy
    @antenna.antenna_accounts.includes_only.where(account_id: account_ids).destroy_all
    render_empty
  end

  private

  def set_antenna
    @antenna = Antenna.where(account: current_account).find(params[:antenna_id])
  end

  def load_accounts
    @antenna.accounts.merge(AntennaAccount.includes_only).without_suspended.includes(:account_stat, :user)
  end

  def account_ids
    Array(resource_params[:account_ids])
  end

  def resource_params
    params.permit(account_ids: [])
  end

  def validate_limit!
    raise Mastodon::ValidationError, I18n.t('antennas.errors.too_many_accounts') if @antenna.antenna_accounts.includes_only.count > Antenna::ACCOUNTS_PER_ANTENNA_LIMIT
  end
end
