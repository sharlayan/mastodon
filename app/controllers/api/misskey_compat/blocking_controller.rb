# frozen_string_literal: true

class Api::MisskeyCompat::BlockingController < Api::MisskeyCompat::BaseController
  before_action :require_user!
  before_action :set_target!

  def create
    BlockService.new.call(current_account, @target)
    render json: MisskeyCompat::UserSerializer.serialize(@target, detailed: true)
  end

  def destroy
    UnblockService.new.call(current_account, @target)
    render json: MisskeyCompat::UserSerializer.serialize(@target, detailed: true)
  end

  private

  def set_target!
    @target = Account.find(params[:userId])
  rescue ActiveRecord::RecordNotFound
    render_error('No such user', 'NO_SUCH_USER', 404)
  end
end
