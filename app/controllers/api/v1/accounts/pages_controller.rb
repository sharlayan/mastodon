# frozen_string_literal: true

class Api::V1::Accounts::PagesController < Api::V1::Accounts::BaseController
  include Api::AnonymousPageViewLimit
  include Api::PageSearchEngineAccess
  include Api::PagesRoleplayAccessConcern

  vary_by 'Authorization, User-Agent'

  before_action :require_feature_enabled!
  before_action -> { authorize_if_got_token! :read, :'read:accounts' }
  before_action :set_account
  before_action :set_booklet, only: :index
  before_action :set_page, only: :show

  def index
    pages = listed_pages
    return not_found if @booklet && !pages&.exists?

    cache_if_unauthenticated!
    @pages = pages.nil? ? [] : paginate_pages(pages)
    render json: @pages, each_serializer: REST::PageSummarySerializer, include_locked_header: true
  end

  def show
    return not_found if page_hidden_from_search_engine?(@page.account)
    return render_page_rate_limit_error if anonymous_page_view_limit_exceeded?(@page)

    cache_if_unauthenticated!
    PageViewTracker.new(@page, account: current_account, request: request).call unless @page.password_visibility? && @page.account_id != current_account&.id
    render json: @page, serializer: REST::PageSerializer
  end

  private

  def require_feature_enabled!
    not_found unless Setting.pages_enabled
  end

  def set_page
    return not_found if @account.unavailable?

    @page = @account.pages.find_by!(name: params[:name])
    return not_found if @page.private_visibility? && @page.account_id != current_account&.id

    not_found if @page.authenticated_visibility? && current_account.nil?
  end

  def set_booklet
    return if params[:booklet_id].blank?
    return not_found unless params[:booklet_id].is_a?(String)

    @booklet = @account.page_series.find_by(id: params[:booklet_id])
    not_found if @booklet.nil?
  end

  def listed_pages
    return if @account.unavailable?
    return if page_hidden_from_search_engine?(@account)

    pages = @account.pages.listed
    pages = pages.where.not(visibility: 'authenticated') if current_account.nil?
    pages = pages.where(page_series_id: @booklet.id) if @booklet
    pages
  end

  def paginate_pages(pages)
    order = @booklet ? { series_position: :asc, id: :asc } : { is_main: :desc, id: :desc }

    pages.summary_columns.includes(:eye_catching_media_attachment, page_series: :cover_media_attachment).order(order)
      .offset([params[:offset].to_s.to_i, 0].max)
      .limit(limit_param(Page::LIST_LIMIT, Page::MAX_LIST_LIMIT))
  end

  def render_page_rate_limit_error
    render json: { error: I18n.t('errors.429') }, status: 429
  end
end
