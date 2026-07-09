# frozen_string_literal: true

class Api::MisskeyCompat::FollowingController < Api::MisskeyCompat::BaseController
  before_action :require_user!
  before_action :set_target!

  def create
    FollowService.new.call(current_account, @target)
    render json: MisskeyCompat::UserSerializer.serialize(@target, detailed: true)
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

  private

  def set_target!
    @target = Account.find(params[:userId])
  rescue ActiveRecord::RecordNotFound
    render_error('No such user', 'NO_SUCH_USER', 404)
  end
end
