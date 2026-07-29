# frozen_string_literal: true

class Api::V1::PageSeriesController < Api::BaseController
  before_action :require_feature_enabled!
  before_action -> { doorkeeper_authorize! :read, :'read:accounts' }, only: [:index]
  before_action -> { doorkeeper_authorize! :write, :'write:accounts' }, except: [:index]
  before_action :require_user!
  before_action :set_series, only: [:update, :destroy]

  def index
    series = current_account.page_series.includes(:pages).order(:title)
    render json: series, each_serializer: REST::PageSeriesSerializer
  end

  def create
    series = current_account.with_lock { current_account.page_series.create!(series_params) }
    render json: series, serializer: REST::PageSeriesSerializer
  end

  def update
    @series.update!(series_params)
    render json: @series, serializer: REST::PageSeriesSerializer
  end

  def destroy
    @series.destroy!
    render_empty
  end

  private

  def require_feature_enabled!
    not_found unless Setting.pages_enabled
  end

  def set_series
    @series = current_account.page_series.find(params[:id])
  end

  def series_params
    params.permit(:title, :description)
  end
end
