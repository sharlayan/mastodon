# frozen_string_literal: true

class Api::MisskeyCompat::GalleryController < Api::MisskeyCompat::BaseController
  NO_SUCH_POST_IDS = {
    'show' => '1137bf14-c5b0-4604-85bb-5b5371b1cd45',
    'destroy' => 'ae52f367-4bd7-4ecd-afc6-5672fff427f5',
    'like' => '56c06af3-1287-442f-9701-c93f7c4a62ff',
    'unlike' => 'c32e6dd0-b555-4413-925e-b3757d19ed84',
  }.freeze
  ACCESS_DENIED_ID = 'c86e09de-1c48-43ac-a435-1c7e42ed4496'
  YOUR_POST_ID = 'f78f1511-5ebc-4478-a888-1198d752da68'
  ALREADY_LIKED_ID = '40e9ed56-a59c-473a-bf3f-f289c54fb5a7'
  NOT_LIKED_ID = 'e3e8e06e-be37-41f7-a5b4-87a8250288f0'
  DEFAULT_LIMIT = 10
  MAX_LIMIT = 100
  POPULAR_LIMIT = 10
  OPTIONAL_AUTHENTICATION_ACTIONS = %i(index featured popular show by_user).freeze

  requires_write_scope :create, :update, :destroy, :like, :unlike
  requires_misskey_permission 'read:account', *OPTIONAL_AUTHENTICATION_ACTIONS
  requires_misskey_permission 'read:gallery', :mine
  requires_misskey_permission 'read:gallery-likes', :likes
  requires_misskey_permission 'write:gallery', :create, :update, :destroy
  requires_misskey_permission 'write:gallery-likes', :like, :unlike

  before_action :require_user!, except: OPTIONAL_AUTHENTICATION_ACTIONS
  before_action :require_user_if_authenticated!, only: OPTIONAL_AUTHENTICATION_ACTIONS
  before_action :require_object_body!, only: [:create, :update]
  before_action :set_post, only: [:show, :update, :destroy, :like, :unlike]

  rescue_from MisskeyCompat::DriveFileResolver::NoSuchFileError do
    render_error('No such file', 'NO_SUCH_FILE', 404)
  end

  rescue_from MisskeyCompat::DriveFileResolver::AmbiguousFileError do
    render_invalid_param('#/properties/fileIds', 'ambiguous file id')
  end

  def index
    render_posts(apply_range(visible_posts).limit(list_limit))
  end

  def featured
    ids = MisskeyGalleryPost.ranking_ids.sort.reverse
    ids = ids.select { |id| id < params[:untilId].to_i } if params[:untilId].present?
    ids = ids.first(list_limit)
    posts = visible_posts.where(id: ids).order(id: :desc)
    render_posts(posts)
  end

  def popular
    render_posts(MisskeyGalleryPost.popular.includes(:account).limit(POPULAR_LIMIT))
  end

  def by_user
    return render_invalid_param('#/properties/userId', 'must be a valid id') unless compat_id?(params[:userId])

    render_posts(apply_range(visible_posts.where(account_id: params[:userId])).limit(list_limit))
  end

  def mine
    render_posts(apply_range(MisskeyGalleryPost.where(account: current_account).includes(:account)).limit(list_limit))
  end

  def likes
    scope = MisskeyGalleryLike.where(account: current_account).joins(misskey_gallery_post: :account).merge(Account.without_suspended)
    likes = apply_range(scope).includes(misskey_gallery_post: :account).limit(list_limit).to_a
    posts = MisskeyCompat::GalleryPostSerializer.serialize_many(likes.map(&:misskey_gallery_post), current_account: current_account)
    render json: likes.zip(posts).map { |like, post| { id: MisskeyCompat::MiId.encode(like.id), post: post } }
  end

  def show
    render json: serialize(@post)
  end

  def create
    return unless valid_post_params?(create: true)
    return if rate_limited?(:misskey_gallery_post_create)

    post = MisskeyGalleryPost.transaction do
      MisskeyGalleryPost.create!(post_attributes.merge(account: current_account, media_attachment_ids: resolve_media_ids(params[:fileIds])))
    end
    render json: serialize(post)
  end

  def update
    return render_no_such_post if @post.account_id != current_account.id
    return unless valid_post_params?(create: false)
    return if rate_limited?(:misskey_gallery_post_update)

    MisskeyGalleryPost.transaction do
      attributes = post_attributes
      attributes[:media_attachment_ids] = resolve_media_ids(params[:fileIds], post: @post) if params.key?(:fileIds)
      @post.update!(attributes.merge(updated_at: Time.current))
    end
    render json: serialize(@post.reload)
  end

  def destroy
    return render_error('Access denied', 'ACCESS_DENIED', 403, id: ACCESS_DENIED_ID) unless @post.account_id == current_account.id || current_user.can?(:manage_reports)

    @post.destroy!
    head 204
  end

  def like
    return render_error('You cannot like your post', 'YOUR_POST', 400, id: YOUR_POST_ID) if @post.account_id == current_account.id
    return render_already_liked if @post.likes.exists?(account_id: current_account.id)

    @post.likes.create!(account: current_account)
    head 204
  rescue ActiveRecord::RecordNotUnique
    render_already_liked
  end

  def unlike
    like = @post.likes.find_by(account_id: current_account.id)
    return render_error('You have not liked that post', 'NOT_LIKED', 400, id: NOT_LIKED_ID) if like.nil?

    like.destroy!
    head 204
  end

  private

  def visible_posts
    MisskeyGalleryPost.available_accounts.includes(:account)
  end

  def set_post
    @post = visible_posts.find_by(id: params[:postId]) if compat_id?(params[:postId])
    render_no_such_post if @post.nil?
  end

  def render_no_such_post
    render_error('No such post', 'NO_SUCH_POST', 404, id: NO_SUCH_POST_IDS[action_name])
  end

  def render_already_liked
    render_error('The post has already been liked', 'ALREADY_LIKED', 400, id: ALREADY_LIKED_ID)
  end

  def require_object_body!
    object_body!
  end

  def list_limit
    pagination_limit(default: DEFAULT_LIMIT, max: MAX_LIMIT)
  end

  def apply_range(scope)
    table = scope.klass.table_name
    scope = apply_compat_pagination_dates(scope)
    scope = scope.where("#{table}.id < ?", params[:untilId].to_i) if params[:untilId].present?
    scope = scope.where("#{table}.id > ?", params[:sinceId].to_i) if params[:sinceId].present?
    scope.reorder(Arel.sql("#{table}.id #{forward_pagination? ? 'ASC' : 'DESC'}"))
  end

  def valid_post_params?(create:)
    valid_title?(required: create) && valid_description? && valid_file_ids?(required: create) && valid_sensitive?
  end

  def valid_title?(required:)
    return true if !required && !params.key?(:title)

    value = params[:title]
    return true if value.is_a?(String) && value.length.between?(1, MisskeyGalleryPost::TITLE_LENGTH_LIMIT)

    render_invalid_param('#/properties/title', "must be a string of 1 to #{MisskeyGalleryPost::TITLE_LENGTH_LIMIT} characters")
    false
  end

  def valid_description?
    value = params[:description]
    return true if value.nil? || (value.is_a?(String) && value.length <= MisskeyGalleryPost::DESCRIPTION_LENGTH_LIMIT)

    render_invalid_param('#/properties/description', "must be null or a string of at most #{MisskeyGalleryPost::DESCRIPTION_LENGTH_LIMIT} characters")
    false
  end

  def valid_file_ids?(required:)
    return true if !required && !params.key?(:fileIds)

    ids = params[:fileIds]
    return true if ids.is_a?(Array) && ids.size.between?(1, MisskeyGalleryPost::FILES_LIMIT) && ids.all? { |id| compat_id?(id) } && ids.uniq.size == ids.size

    render_invalid_param('#/properties/fileIds', "must be an array of 1 to #{MisskeyGalleryPost::FILES_LIMIT} unique ids")
    false
  end

  def valid_sensitive?
    return true if !params.key?(:isSensitive) || [true, false].include?(params[:isSensitive])

    render_invalid_param('#/properties/isSensitive', 'must be boolean')
    false
  end

  def post_attributes
    attributes = {}
    attributes[:title] = params[:title] if params.key?(:title)
    attributes[:description] = params[:description] if params.key?(:description)
    attributes[:sensitive] = params[:isSensitive] if params.key?(:isSensitive)
    attributes
  end

  def resolve_media_ids(ids, post: nil)
    ids = ids.map(&:to_s)
    existing = post ? post.media_attachments.where(drive_file_id: ids).index_by { |media| media.drive_file_id.to_s } : {}
    pending = ids.reject { |id| existing.key?(id) }
    resolved = MisskeyCompat::DriveFileResolver.new.call(account: current_account, file_ids: pending, allow_drive_files: Setting.drive_enabled)
    resolved_by_id = pending.zip(resolved).to_h

    ids.map { |id| (existing[id]&.id || resolved_by_id[id]).to_i }
  end

  def serialize(post)
    MisskeyCompat::GalleryPostSerializer.serialize(post, current_account: current_account)
  end

  def render_posts(posts)
    render json: MisskeyCompat::GalleryPostSerializer.serialize_many(posts.to_a, current_account: current_account)
  end
end
