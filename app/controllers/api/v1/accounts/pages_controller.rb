# frozen_string_literal: true

class Api::V1::Accounts::PagesController < Api::BaseController
  include Api::AnonymousPageViewLimit
  include Api::PageSearchEngineAccess

  vary_by 'Authorization, User-Agent'

  before_action :require_feature_enabled!
  before_action -> { authorize_if_got_token! :read, :'read:accounts' }
  before_action :set_account
  before_action :set_page, only: :show

  def index
    cache_if_unauthenticated!
    @pages = load_pages
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

  def set_account
    @account = Account.find(params[:account_id])
  end

  def set_page
    not_found if @account.unavailable?
    @page = @account.pages.find_by!(name: params[:name])
    not_found if @page.private_visibility? && @page.account_id != current_account&.id
    not_found if @page.authenticated_visibility? && current_account.nil?
  end

  def load_pages
    return [] if @account.unavailable?
    return [] if page_hidden_from_search_engine?(@account)

    pages = @account.pages.listed
    pages = pages.where.not(visibility: 'authenticated') if current_account.nil?

    pages.includes(page_series: :cover_media_attachment).order(is_main: :desc, id: :desc)
      .offset([params[:offset].to_i, 0].max)
      .limit(limit_param(Page::LIST_LIMIT, Page::MAX_LIST_LIMIT))
  end

  def render_page_rate_limit_error
    render json: { error: I18n.t('errors.429') }, status: 429
  end
end
