# frozen_string_literal: true

class Api::MisskeyCompat::PagesController < Api::MisskeyCompat::BaseController
  include Api::PagesRoleplayAccessConcern

  ALLOWED_BLOCK_KEYS = %w(id type text title children fileId noUpscale note detailed).freeze
  OWNER_ACTIONS = %i(index likes create update destroy like unlike).freeze

  requires_write_scope :create, :update, :destroy, :like, :unlike

  before_action :require_pages_enabled!
  before_action :require_user!, only: OWNER_ACTIONS
  before_action :set_page, only: [:update, :destroy, :like, :unlike]
  before_action :authorize_owner!, only: [:update, :destroy]

  rescue_from MisskeyCompat::DriveFileResolver::NoSuchFileError do
    render_error('No such file', 'NO_SUCH_FILE', 404)
  end

  rescue_from MisskeyCompat::DriveFileResolver::AmbiguousFileError do
    render_invalid_param('#/properties/eyeCatchingImageId', 'ambiguous file id')
  end

  rescue_from Page::ContentLimitError do
    render_invalid_param('#/properties/content', 'content exceeds the allowed limits')
  end

  def featured
    pages = Page.featured.includes(:account, :eye_catching_media_attachment).limit(10)
    render json: serialize_many(pages)
  end

  def index
    pages = apply_page_range(current_account.pages).includes(:account, :eye_catching_media_attachment).limit(pagination_limit(default: 10, max: 100))
    render json: serialize_many(pages)
  end

  def likes
    likes = apply_like_range(current_account.page_likes.joins(:page).merge(Page.published)).includes(page: [:account, :eye_catching_media_attachment]).limit(pagination_limit(default: 10, max: 100))
    render json: likes.map { |like| { id: MisskeyCompat::MiId.encode(like.id), page: serialize(like.page) } }
  end

  def by_user
    pages = apply_page_range(Page.published.where(account_id: params[:userId])).includes(:account, :eye_catching_media_attachment).limit(pagination_limit(default: 10, max: 100))
    render json: serialize_many(pages)
  end

  def show
    page = find_shown_page
    return render_no_such_page if page.nil? || (!page.public_visibility? && page.account_id != current_account&.id)

    render json: serialize(page)
  end

  def create
    page = Page.transaction { current_account.pages.create!(page_attributes(create: true)) }
    render json: serialize(page)
  rescue ActiveRecord::RecordInvalid => e
    render_page_validation_error(e.record)
  end

  def update
    Page.transaction { @page.update!(page_attributes(create: false)) }
    head 204
  rescue ActiveRecord::RecordInvalid => e
    render_page_validation_error(e.record)
  end

  def destroy
    @page.destroy!
    head 204
  end

  def like
    return render_error('You cannot like your page', 'YOUR_PAGE', 400) if @page.account_id == current_account.id
    return render_error('The page has already been liked', 'ALREADY_LIKED', 400) if @page.page_likes.exists?(account_id: current_account.id)

    @page.page_likes.create!(account: current_account)
    head 204
  end

  def unlike
    like = @page.page_likes.find_by(account_id: current_account.id)
    return render_error('You have not liked that page', 'NOT_LIKED', 400) if like.nil?

    like.destroy!
    head 204
  end

  private

  def require_pages_enabled!
    render_error('Pages are not available on this server', 'UNAVAILABLE', 400) unless Setting.pages_enabled
  end

  def set_page
    @page = Page.find_by(id: params[:pageId])
    hidden_page = @page && (@page.account.unavailable? || (!@page.public_visibility? && (@page.account_id != current_account&.id || %w(like unlike).include?(action_name))))
    render_no_such_page if @page.nil? || hidden_page
  end

  def authorize_owner!
    render_error('Access denied', 'ACCESS_DENIED', 403) unless @page.account_id == current_account.id
  end

  def find_shown_page
    if params[:pageId].present?
      Page.available_accounts.includes(:account, :eye_catching_media_attachment).find_by(id: params[:pageId])
    elsif params[:name].present? && params[:username].present?
      account = Account.where(domain: nil).where('LOWER(username) = ?', params[:username].to_s.downcase).first
      account&.pages&.published&.includes(:account, :eye_catching_media_attachment)&.find_by(name: params[:name]) unless account&.unavailable?
    end
  end

  def page_attributes(create:)
    attributes = {}
    {
      title: :title,
      name: :name,
      summary: :summary,
      font: :font,
      alignCenter: :align_center,
      hideTitleWhenPinned: :hide_title_when_pinned,
    }.each do |source, target|
      attributes[target] = params[source] if params.key?(source)
    end

    attributes[:content] = resolved_content if params.key?(:content)
    attributes[:eye_catching_media_attachment_id] = resolved_eye_catching_media_id if params.key?(:eyeCatchingImageId)
    attributes[:content] ||= [] if create
    attributes
  end

  def resolved_content
    content = sanitize_blocks(params[:content])
    file_ids = collect_blocks(content).filter_map { |block| block['fileId'].presence if block['type'] == 'image' }.uniq
    resolved_ids = resolve_media_ids(file_ids.map { |id| MisskeyCompat::MiId.decode(id) })
    mapping = file_ids.zip(resolved_ids).to_h

    transform_blocks(content) do |block|
      block['fileId'] = mapping[block['fileId']] if block['type'] == 'image' && block['fileId'].present?
      block['note'] = MisskeyCompat::MiId.decode(block['note']) if block['type'] == 'note' && block['note'].present?
    end
  end

  def resolved_eye_catching_media_id
    return nil if params[:eyeCatchingImageId].blank?

    resolve_media_ids([params[:eyeCatchingImageId]]).first
  end

  def resolve_media_ids(ids)
    @resolved_page_media_ids ||= {}
    normalized_ids = ids.map(&:to_s)
    missing_ids = normalized_ids.reject { |id| @resolved_page_media_ids.key?(id) }.uniq
    resolved_ids = MisskeyCompat::DriveFileResolver.new.call(
      account: current_account,
      file_ids: missing_ids,
      allow_drive_files: Setting.drive_enabled
    )
    @resolved_page_media_ids.merge!(missing_ids.zip(resolved_ids).to_h)
    normalized_ids.map { |id| @resolved_page_media_ids[id] }
  end

  def sanitize_blocks(blocks, depth = 1)
    raise Page::ContentLimitError if depth > Page::MAX_BLOCK_DEPTH && Array(blocks).present?
    return [] if depth > Page::MAX_BLOCK_DEPTH

    Array(blocks).filter_map do |block|
      block = block.to_unsafe_h if block.respond_to?(:to_unsafe_h)
      next unless block.is_a?(Hash)

      clean = block.stringify_keys.slice(*ALLOWED_BLOCK_KEYS)
      clean['noUpscale'] = ActiveModel::Type::Boolean.new.cast(clean['noUpscale']) if clean['type'] == 'image' && clean.key?('noUpscale')
      clean['children'] = sanitize_blocks(clean['children'], depth + 1) if clean.key?('children')
      clean
    end
  end

  def collect_blocks(blocks, accumulator = [])
    Array(blocks).each do |block|
      accumulator << block
      collect_blocks(block['children'], accumulator) if block['children'].is_a?(Array)
    end
    accumulator
  end

  def transform_blocks(blocks, &)
    blocks.each do |item|
      yield item
      transform_blocks(item['children'], &) if item['children'].is_a?(Array)
    end
    blocks
  end

  def apply_page_range(scope)
    scope = apply_compat_date_range(scope)
    scope = scope.where(pages: { id: ...(params[:untilId].to_i) }) if params[:untilId].present?
    scope = scope.where('pages.id > ?', params[:sinceId].to_i) if params[:sinceId].present?
    scope.order('pages.id DESC')
  end

  def apply_like_range(scope)
    scope = scope.where(page_likes: { created_at: ...(compat_time(params[:untilDate])) }) if params[:untilDate].present?
    scope = scope.where(page_likes: { created_at: (compat_time(params[:sinceDate])).. }) if params[:sinceDate].present?
    scope = scope.where(page_likes: { id: ...(params[:untilId].to_i) }) if params[:untilId].present?
    scope = scope.where('page_likes.id > ?', params[:sinceId].to_i) if params[:sinceId].present?
    scope.order('page_likes.id DESC')
  end

  def serialize(page)
    MisskeyCompat::PageSerializer.serialize(page, current_account: current_account)
  end

  def serialize_many(pages)
    pages.map { |page| serialize(page) }
  end

  def render_no_such_page
    render_error('No such page', 'NO_SUCH_PAGE', 404)
  end

  def render_page_validation_error(page)
    if page.errors.added?(:name, :taken)
      render_error('Specified name already exists', 'NAME_ALREADY_EXISTS', 400)
    else
      render_error(page.errors.full_messages.to_sentence, 'INVALID_PARAM', 400)
    end
  end
end
