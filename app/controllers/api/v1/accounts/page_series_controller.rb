# frozen_string_literal: true

class Api::V1::Accounts::PageSeriesController < Api::V1::Accounts::BaseController
  include Api::PageSearchEngineAccess

  vary_by 'Authorization, User-Agent'

  before_action :require_feature_enabled!
  before_action -> { authorize_if_got_token! :read, :'read:accounts' }
  before_action :set_account

  def index
    return render json: [] if @account.unavailable? || page_hidden_from_search_engine?(@account)

    series = @account.page_series
      .where(id: Page.where(visibility: 'public', draft: false).select(:page_series_id))
      .includes(:account, :main_page, :cover_media_attachment, :pages)
      .order(updated_at: :desc)
    render json: series, each_serializer: REST::PageSeriesSerializer
  end

  private

  def require_feature_enabled!
    not_found unless Setting.pages_enabled
  end
end
