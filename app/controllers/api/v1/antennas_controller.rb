# frozen_string_literal: true

class Api::V1::AntennasController < Api::BaseController
  include Api::AntennaFeatureConcern

  before_action -> { doorkeeper_authorize! :read, :'read:lists' }, only: [:index, :show]
  before_action -> { doorkeeper_authorize! :write, :'write:lists' }, except: [:index, :show]

  before_action :require_user!
  before_action :set_antenna, except: [:index, :create]

  def index
    @antennas = Antenna.where(account: current_account).includes(:antenna_accounts, :antenna_domains, antenna_tags: :tag)
    render json: @antennas, each_serializer: REST::AntennaSerializer
  end

  def show
    render json: @antenna, serializer: REST::AntennaSerializer
  end

  def create
    @antenna = current_account.with_lock { current_account.antennas.create!(antenna_params) }
    render json: @antenna, serializer: REST::AntennaSerializer
  end

  def update
    @antenna.update!(antenna_params)
    render json: @antenna, serializer: REST::AntennaSerializer
  end

  def destroy
    @antenna.destroy!
    render_empty
  end

  private

  def set_antenna
    @antenna = Antenna.where(account: current_account).find(params[:id])
  end

  def antenna_params
    params.permit(
      :title, :available, :with_media_only, :ignore_reblog,
      :any_keywords, :any_accounts, :any_domains, :any_tags,
      keywords: [], exclude_keywords: []
    )
  end
end
