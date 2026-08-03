# frozen_string_literal: true

class Api::V1::Accounts::ExcludeAntennasController < Api::V1::Accounts::BaseController
  include Api::AntennaFeatureConcern

  before_action -> { doorkeeper_authorize! :read, :'read:lists' }
  before_action :require_user!
  before_action :set_account

  def index
    @antennas = if @account.suspended?
                  []
                else
                  Antenna.where(account: current_account).select { |antenna| antenna.exclude_accounts.map(&:to_i).include?(@account.id) }
                end
    render json: @antennas, each_serializer: REST::AntennaSerializer
  end
end
