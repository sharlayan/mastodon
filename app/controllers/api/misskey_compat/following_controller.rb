# frozen_string_literal: true

class Api::MisskeyCompat::FollowingController < Api::MisskeyCompat::BaseController
  requires_write_scope :create, :update, :update_all, :destroy, :accept_request, :reject_request, :cancel_request, :invalidate
  requires_misskey_permission 'read:following', :requests, :index, :sent_requests
  requires_misskey_permission 'write:following', :create, :update, :update_all, :destroy, :accept_request, :reject_request, :cancel_request, :invalidate

  NOTIFY_VALUES = %w(normal none).freeze

  before_action :require_user!
  before_action :set_target!, except: [:requests, :index, :sent_requests, :update_all]

  def index
    scope = current_account.active_relationships.includes(:target_account)
    scope = scope.where(notify: true) if ActiveModel::Type::Boolean.new.cast(params[:notification])
    follows = paginate_by_id(scope).to_a
    collection = MisskeyCompat::UserCollectionContext.for(follows.map(&:target_account), viewer: current_account)

    render json: follows.map { |follow| serialize_following(follow, collection) }
  end

  def create
    return render_error('Followee is yourself', 'FOLLOWEE_IS_YOURSELF', 400, id: '26fbe7bb-a331-4857-af17-205b426669a9') if @target.id == current_account.id
    return render_error('You are blocked by that user', 'BLOCKED', 400, id: 'c4ab57cc-4e41-45e9-bfd9-584f61e35ce0') if @target.blocking?(current_account)
    return render_error('You are blocking that user', 'BLOCKING', 400, id: '4e2206ec-aa4f-4960-b865-6c23ac38e2d9') if current_account.blocking?(@target)

    FollowService.new.call(current_account, @target)
    render json: MisskeyCompat::UserSerializer.serialize(@target, detailed: true)
  end

  def requests
    render json: paginated_requests.map { |request| serialize_request(request) }
  end

  def sent_requests
    requests = paginate_by_id(FollowRequest.where(account_id: current_account.id).includes(:target_account))
    render json: requests.map { |request| serialize_sent_request(request) }
  end

  def update_all
    return render_invalid_param('#/properties/notify', 'must be equal to one of the allowed values') if params.key?(:notify) && NOTIFY_VALUES.exclude?(params[:notify])
    return if rate_limited?(:misskey_compat_following_update_all)

    update_all_notify(params[:notify] == 'normal') if params.key?(:notify)
    head 204
  end

  def update
    follow = current_account.active_relationships.find_by(target_account: @target)
    return render_error('You are not following that user', 'NOT_FOLLOWING', 400) if follow.nil?

    follow.update!(notify: params[:notify].to_s == 'normal') if params.key?(:notify)

    render json: MisskeyCompat::UserSerializer.serialize(@target)
  end

  def destroy
    UnfollowService.new.call(current_account, @target)
    render json: MisskeyCompat::UserSerializer.serialize(@target, detailed: true)
  end

  def accept_request
    return render_error('No follow request', 'NO_FOLLOW_REQUEST', 400, id: 'bcde4f8b-0913-4614-8881-614e522fb041') unless @target.requested?(current_account)

    AuthorizeFollowService.new.call(@target, current_account)
    head 204
  end

  def reject_request
    RejectFollowService.new.call(@target, current_account) if @target.requested?(current_account)
    head 204
  end

  def cancel_request
    return render_error('Follow request not found', 'FOLLOW_REQUEST_NOT_FOUND', 400) unless current_account.requested?(@target)

    UnfollowService.new.call(current_account, @target)
    render json: MisskeyCompat::UserSerializer.serialize(@target)
  end

  def invalidate
    return render_error('Follower is yourself', 'FOLLOWER_IS_YOURSELF', 400) if @target.id == current_account.id
    return render_error('The other user is not following you', 'NOT_FOLLOWING', 400) unless @target.following?(current_account)

    UnfollowService.new.call(@target, current_account)
    render json: MisskeyCompat::UserSerializer.serialize(@target)
  end

  private

  def paginated_requests
    scope = FollowRequest.where(target_account_id: current_account.id).includes(:account).order(id: :desc)
    scope = scope.where(id: ...params[:untilId].to_i) if params[:untilId].present?
    scope = scope.where('follow_requests.id > ?', params[:sinceId].to_i) if params[:sinceId].present?
    scope.limit(pagination_limit(default: 10, max: 100))
  end

  def paginate_by_id(scope)
    table = scope.klass.table_name
    scope = apply_compat_pagination_dates(scope)
    scope = scope.where(id: ...params[:untilId].to_i) if params[:untilId].present?
    scope = scope.where("#{table}.id > ?", params[:sinceId].to_i) if params[:sinceId].present?
    scope.reorder(id: forward_pagination? ? :asc : :desc).limit(pagination_limit(default: 10, max: 100))
  end

  def update_all_notify(notify)
    follows = current_account.active_relationships.where.not(notify: notify)
    target_ids = follows.pluck(:target_account_id)
    return if target_ids.empty?

    follows.update_all(notify: notify, updated_at: Time.now.utc)
    Rails.cache.delete_multi(target_ids.flat_map { |id| [['relationships', current_account.id, id], ['relationships', id, current_account.id]] })
  end

  def serialize_following(follow, collection)
    {
      id: MisskeyCompat::MiId.encode(follow.id),
      createdAt: follow.created_at.iso8601,
      followeeId: MisskeyCompat::MiId.encode(follow.target_account_id),
      followerId: MisskeyCompat::MiId.encode(follow.account_id),
      followee: MisskeyCompat::UserSerializer.serialize(follow.target_account, detailed: true, viewer: current_account, relationships: collection.relationships, collection:),
    }
  end

  def serialize_sent_request(request)
    {
      id: MisskeyCompat::MiId.encode(request.id),
      follower: MisskeyCompat::UserSerializer.serialize(current_account),
      followee: MisskeyCompat::UserSerializer.serialize(request.target_account),
    }
  end

  def serialize_request(request)
    {
      id: MisskeyCompat::MiId.encode(request.id),
      follower: MisskeyCompat::UserSerializer.serialize(request.account),
      followee: MisskeyCompat::UserSerializer.serialize(current_account),
    }
  end

  def set_target!
    @target = Account.without_requested_deletion.find(params[:userId])
  rescue ActiveRecord::RecordNotFound
    render_error('No such user', 'NO_SUCH_USER', 404)
  end
end
