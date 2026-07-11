# frozen_string_literal: true

class Api::V1::PagesController < Api::BaseController
  ALLOWED_BLOCK_KEYS = %w(id type text title children fileId note detailed).freeze

  before_action :require_feature_enabled!
  before_action -> { doorkeeper_authorize! :read, :'read:accounts' }, only: [:index, :show, :featured]
  before_action -> { doorkeeper_authorize! :write, :'write:accounts' }, except: [:index, :show, :featured]

  before_action :require_user!, except: [:show, :featured]
  before_action :set_page, only: [:show, :update, :destroy, :like, :unlike]

  def index
    @pages = current_account.pages.order(id: :desc).to_a
    render json: @pages, each_serializer: REST::PageSerializer
  end

  def show
    render json: @page, serializer: REST::PageSerializer
  end

  def featured
    @pages = Page.featured.limit(10).to_a
    render json: @pages, each_serializer: REST::PageSerializer
  end

  def create
    @page = current_account.pages.create!(page_params)
    render json: @page, serializer: REST::PageSerializer
  end

  def update
    authorize_owner!
    @page.update!(page_params)
    render json: @page, serializer: REST::PageSerializer
  end

  def destroy
    authorize_owner!
    @page.destroy!
    render_empty
  end

  def like
    render json: { error: I18n.t('pages.errors.own_page') }, status: 422 and return if @page.account_id == current_account.id

    PageLike.find_or_create_by!(account: current_account, page: @page)
    @page.reload
    render json: @page, serializer: REST::PageSerializer
  end

  def unlike
    PageLike.find_by(account: current_account, page: @page)&.destroy
    @page.reload
    render json: @page, serializer: REST::PageSerializer
  end

  private

  def require_feature_enabled!
    not_found unless Setting.pages_enabled
  end

  def set_page
    @page = Page.find(params[:id])
  end

  def authorize_owner!
    not_found unless @page.account_id == current_account.id
  end

  def page_params
    params.permit(:title, :name, :summary, :align_center, :hide_title_when_pinned, :font, :eye_catching_media_attachment_id).merge(content_params)
  end

  def content_params
    return {} unless params.key?(:content)

    { content: sanitize_blocks(params[:content]) }
  end

  def sanitize_blocks(blocks)
    Array(blocks).filter_map do |block|
      block = block.to_unsafe_h if block.respond_to?(:to_unsafe_h)
      next unless block.is_a?(Hash)

      block = block.stringify_keys.slice(*ALLOWED_BLOCK_KEYS)
      block['children'] = sanitize_blocks(block['children']) if block.key?('children')
      block
    end
  end
end
