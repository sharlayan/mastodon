# frozen_string_literal: true

class Api::V1::PagesController < Api::BaseController
  include Api::AnonymousPageViewLimit
  include Api::PageSearchEngineAccess

  ALLOWED_BLOCK_KEYS = %w(id type text format title children fileId noUpscale spoiler note detailed url size).freeze

  vary_by 'Authorization, User-Agent'

  before_action :require_feature_enabled!
  before_action -> { doorkeeper_authorize! :read, :'read:accounts' }, only: [:index, :categories, :featured]
  before_action -> { authorize_if_got_token! :read, :'read:accounts' }, only: [:show, :unlock]
  before_action -> { doorkeeper_authorize! :write, :'write:accounts' }, except: [:index, :categories, :show, :featured, :unlock]

  before_action :require_user!, except: [:show, :unlock]
  before_action :set_page, only: [:show, :update, :destroy, :like, :unlike, :set_main, :unset_main, :set_series_main, :unset_series_main]

  rescue_from Page::ContentLimitError do
    render json: { error: 'Page content exceeds the allowed limits' }, status: 422
  end

  def index
    @pages = current_account.pages.includes(page_series: :cover_media_attachment).order(is_main: :desc, id: :desc)
      .offset([params[:offset].to_i, 0].max)
      .limit(limit_param(Page::LIST_LIMIT, Page::MAX_LIST_LIMIT))
    render json: @pages, each_serializer: REST::PageSummarySerializer
  end

  def categories
    render json: current_account.pages.where.not(category: [nil, '']).distinct.pluck(:category)
  end

  def show
    return not_found if @page.private_visibility? && @page.account_id != current_account&.id
    return not_found if @page.authenticated_visibility? && current_account.nil?
    return not_found if page_hidden_from_search_engine?(@page.account)
    return render_page_rate_limit_error if anonymous_page_view_limit_exceeded?(@page)

    cache_if_unauthenticated!
    track_page_view(@page) unless @page.password_visibility? && @page.account_id != current_account&.id
    render json: @page, serializer: REST::PageSerializer
  end

  def unlock
    @page = Page.find(params[:id])
    return not_found if @page.account.unavailable? || (!@page.password_visibility? && @page.account_id != current_account&.id)

    unlocked = @page.account_id == current_account&.id || @page.valid_access_password?(params[:password]) || @page.valid_access_token?(params[:access_token])
    render json: { error: I18n.t('pages.errors.invalid_password') }, status: 403 and return unless unlocked

    track_page_view(@page)
    render json: {
      page: ActiveModelSerializers::SerializableResource.new(@page, serializer: REST::PageSerializer, scope_name: :current_user, scope: current_user, page_unlocked: true),
      access_token: @page.access_token,
    }
  end

  def featured
    @pages = Page.featured.includes(page_series: :cover_media_attachment).limit(Page::LIST_LIMIT).to_a
    render json: @pages, each_serializer: REST::PageSummarySerializer
  end

  def create
    current_account.with_lock do
      @page = current_account.pages.create!(page_params)
    end
    render json: @page, serializer: REST::PageSerializer, page_unlocked: true
  end

  def update
    authorize_owner!
    @page.update!(page_params)
    render json: @page, serializer: REST::PageSerializer, page_unlocked: true
  end

  def destroy
    authorize_owner!
    @page.destroy!
    render_empty
  end

  def like
    not_found unless page_accessible?
    render json: { error: I18n.t('pages.errors.own_page') }, status: 422 and return if @page.account_id == current_account.id

    PageLike.find_or_create_by!(account: current_account, page: @page)
    @page.reload
    render json: @page, serializer: REST::PageSerializer, page_unlocked: true
  end

  def unlike
    not_found unless page_accessible?
    PageLike.find_by(account: current_account, page: @page)&.destroy
    @page.reload
    render json: @page, serializer: REST::PageSerializer, page_unlocked: true
  end

  def set_main
    authorize_owner!
    return not_found unless @page.eligible_for_main?

    Page.transaction do
      current_account.pages.where(is_main: true).update_all(is_main: false)
      @page.update!(is_main: true)
    end

    render json: @page, serializer: REST::PageSerializer, page_unlocked: true
  end

  def unset_main
    authorize_owner!
    @page.update!(is_main: false)
    render json: @page, serializer: REST::PageSerializer, page_unlocked: true
  end

  def set_series_main
    authorize_owner!

    Page.transaction do
      @page.lock!
      return not_found unless @page.eligible_for_main? && @page.page_series

      @page.page_series.with_lock do
        ordered_pages = @page.page_series.pages.lock.to_a
        ordered_pages = [@page] + ordered_pages.reject { |page| page.id == @page.id }
        ordered_pages.each_with_index do |page, position|
          page.update_column(:series_position, position) if page.series_position != position
        end
        @page.page_series.update!(main_page: @page)
      end
    end

    @page.reload
    render json: @page, serializer: REST::PageSerializer, page_unlocked: true
  end

  def unset_series_main
    authorize_owner!

    Page.transaction do
      @page.lock!
      return not_found unless @page.page_series

      @page.page_series.with_lock do
        @page.page_series.update!(main_page: nil) if @page.page_series.main_page_id == @page.id
      end
    end

    render json: @page, serializer: REST::PageSerializer, page_unlocked: true
  end

  private

  def require_feature_enabled!
    not_found unless Setting.pages_enabled
  end

  def set_page
    @page = Page.find(params[:id])
    return not_found if @page.account.unavailable?

    not_found if @page.private_visibility? && @page.account_id != current_account&.id
    not_found if @page.authenticated_visibility? && current_account.nil?
  end

  def authorize_owner!
    not_found unless @page.account_id == current_account.id
  end

  def render_page_rate_limit_error
    render json: { error: I18n.t('errors.429') }, status: 429
  end

  def track_page_view(page)
    PageViewTracker.new(page, account: current_account, request: request).call
  end

  def page_params
    permitted = params.permit(:title, :name, :summary, :category, :draft, :visibility, :password, :align_center, :hide_title_when_pinned, :font, :eye_catching_media_attachment_id, :booklet_id, :booklet_position).merge(content_params)
    permitted[:page_series_id] = permitted.delete(:booklet_id) if permitted.key?(:booklet_id)
    permitted[:series_position] = permitted.delete(:booklet_position) if permitted.key?(:booklet_position)
    if permitted.key?(:draft) && !permitted.key?(:visibility)
      permitted[:visibility] = ActiveModel::Type::Boolean.new.cast(permitted[:draft]) ? 'private' : 'public'
    end
    permitted[:access_password] = permitted.delete(:password) if permitted.key?(:password)
    permitted
  end

  def page_accessible?
    @page.public_visibility? ||
      @page.authenticated_visibility? ||
      @page.account_id == current_account&.id ||
      (@page.password_visibility? && @page.valid_access_token?(params[:access_token]))
  end

  def content_params
    return {} unless params.key?(:content)

    { content: sanitize_blocks(params[:content]) }
  end

  def sanitize_blocks(blocks, depth = 1)
    raise Page::ContentLimitError if depth > Page::MAX_BLOCK_DEPTH && Array(blocks).present?
    return [] if depth > Page::MAX_BLOCK_DEPTH

    Array(blocks).filter_map do |block|
      block = block.to_unsafe_h if block.respond_to?(:to_unsafe_h)
      next unless block.is_a?(Hash)

      block = block.stringify_keys.slice(*ALLOWED_BLOCK_KEYS)
      block['noUpscale'] = ActiveModel::Type::Boolean.new.cast(block['noUpscale']) if block['type'] == 'image' && block.key?('noUpscale')
      if Page::SPOILER_BLOCK_TYPES.include?(block['type'])
        block['spoiler'] = ActiveModel::Type::Boolean.new.cast(block['spoiler']) if block.key?('spoiler')
      else
        block.delete('spoiler')
      end
      block['children'] = sanitize_blocks(block['children'], depth + 1) if block.key?('children')
      block
    end
  end
end
