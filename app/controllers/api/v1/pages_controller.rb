# frozen_string_literal: true

class Api::V1::PagesController < Api::BaseController
  ALLOWED_BLOCK_KEYS = %w(id type text title children fileId noUpscale note detailed url size).freeze

  before_action :require_feature_enabled!
  before_action -> { doorkeeper_authorize! :read, :'read:accounts' }, only: [:index, :categories]
  before_action -> { authorize_if_got_token! :read, :'read:accounts' }, only: [:show, :featured, :unlock]
  before_action -> { doorkeeper_authorize! :write, :'write:accounts' }, except: [:index, :categories, :show, :featured, :unlock]

  before_action :require_user!, except: [:show, :featured, :unlock]
  before_action :set_page, only: [:show, :update, :destroy, :like, :unlike, :set_main, :unset_main]

  rescue_from Page::ContentLimitError do
    render json: { error: 'Page content exceeds the allowed limits' }, status: 422
  end

  def index
    @pages = current_account.pages.order(is_main: :desc, id: :desc).to_a
    render json: @pages, each_serializer: REST::PageSerializer
  end

  def categories
    render json: current_account.pages.where.not(category: [nil, '']).distinct.pluck(:category)
  end

  def show
    not_found if @page.private_visibility? && @page.account_id != current_account&.id
    render json: @page, serializer: REST::PageSerializer
  end

  def unlock
    @page = Page.find(params[:id])
    return not_found if @page.account.unavailable? || (!@page.password_visibility? && @page.account_id != current_account&.id)

    unlocked = @page.account_id == current_account&.id || @page.valid_access_password?(params[:password]) || @page.valid_access_token?(params[:access_token])
    render json: { error: I18n.t('pages.errors.invalid_password') }, status: 403 and return unless unlocked

    render json: {
      page: ActiveModelSerializers::SerializableResource.new(@page, serializer: REST::PageSerializer, scope_name: :current_user, scope: current_user, page_unlocked: true),
      access_token: @page.access_token,
    }
  end

  def featured
    @pages = Page.featured.limit(10).to_a
    render json: @pages, each_serializer: REST::PageSerializer
  end

  def create
    @page = current_account.pages.create!(page_params)
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
    not_found unless @page.eligible_for_main?

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

  private

  def require_feature_enabled!
    not_found unless Setting.pages_enabled
  end

  def set_page
    @page = Page.find(params[:id])
    return not_found if @page.account.unavailable?

    not_found if @page.private_visibility? && @page.account_id != current_account&.id
  end

  def authorize_owner!
    not_found unless @page.account_id == current_account.id
  end

  def page_params
    permitted = params.permit(:title, :name, :summary, :category, :draft, :visibility, :password, :align_center, :hide_title_when_pinned, :font, :eye_catching_media_attachment_id).merge(content_params)
    if permitted.key?(:draft) && !permitted.key?(:visibility)
      permitted[:visibility] = ActiveModel::Type::Boolean.new.cast(permitted[:draft]) ? 'private' : 'public'
    end
    permitted[:access_password] = permitted.delete(:password) if permitted.key?(:password)
    permitted
  end

  def page_accessible?
    @page.public_visibility? || @page.account_id == current_account&.id || (@page.password_visibility? && @page.valid_access_token?(params[:access_token]))
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
      block['children'] = sanitize_blocks(block['children'], depth + 1) if block.key?('children')
      block
    end
  end
end
