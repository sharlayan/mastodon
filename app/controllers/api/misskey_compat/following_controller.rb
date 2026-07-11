# frozen_string_literal: true

class Api::MisskeyCompat::FollowingController < Api::MisskeyCompat::BaseController
  before_action :require_user!
  before_action :set_target!, except: [:requests]

  def create
    FollowService.new.call(current_account, @target)
    render json: MisskeyCompat::UserSerializer.serialize(@target, detailed: true)
  end

  def requests
    render json: paginated_requests.map { |request| serialize_request(request) }
  end

  def destroy
    UnfollowService.new.call(current_account, @target)
    render json: MisskeyCompat::UserSerializer.serialize(@target, detailed: true)
  end

  def accept_request
    AuthorizeFollowService.new.call(@target, current_account)
    head 204
  end

  def reject_request
    RejectFollowService.new.call(@target, current_account)
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

  def serialize_request(request)
    {
      id: MisskeyCompat::MiId.encode(request.id),
      follower: MisskeyCompat::UserSerializer.serialize(request.account),
      followee: MisskeyCompat::UserSerializer.serialize(current_account),
    }
  end

  def set_target!
    @target = Account.find(params[:userId])
  rescue ActiveRecord::RecordNotFound
    render_error('No such user', 'NO_SUCH_USER', 404)
  end
end
