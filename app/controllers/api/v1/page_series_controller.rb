# frozen_string_literal: true

class Api::V1::PageSeriesController < Api::BaseController
  before_action :require_feature_enabled!
  before_action -> { doorkeeper_authorize! :read, :'read:accounts' }, only: [:index, :others]
  before_action -> { doorkeeper_authorize! :write, :'write:accounts' }, except: [:index, :others]
  before_action :require_user!
  before_action :set_series, only: [:update, :destroy]

  def index
    series = current_account.page_series.includes(:main_page, :pages, :cover_media_attachment).order(:title)
    render json: series, each_serializer: REST::PageSeriesSerializer
  end

  def others
    series = PageSeries
      .where(id: Page.where(visibility: 'public', draft: false).select(:page_series_id))
      .where(displayed: true)
      .where.not(account_id: current_account.id)
      .includes(:account, :main_page, :cover_media_attachment, :pages)
      .order(updated_at: :desc)
      .limit(100)
      .reject { |booklet| booklet.account.unavailable? }
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
    params.permit(:title, :description, :cover_media_attachment_id, :displayed)
  end
end
