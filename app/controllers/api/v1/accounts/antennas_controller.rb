# frozen_string_literal: true

class Api::V1::Accounts::AntennasController < Api::V1::Accounts::BaseController
  include Api::AntennaFeatureConcern

  before_action -> { doorkeeper_authorize! :read, :'read:lists' }
  before_action :require_user!
  before_action :set_account

  def index
    @antennas = if @account.suspended?
                  []
                else
                  Antenna.where(account: current_account, id: AntennaAccount.includes_only.where(account_id: @account.id).select(:antenna_id))
                end
    render json: @antennas, each_serializer: REST::AntennaSerializer
  end
end
