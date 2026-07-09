# frozen_string_literal: true

class Api::MisskeyCompat::MutesController < Api::MisskeyCompat::BaseController
  before_action :require_user!
  before_action :set_target!

  def create
    MuteService.new.call(current_account, @target, notifications: ActiveModel::Type::Boolean.new.cast(params.fetch(:notifications, true)))
    head 204
  end

  def destroy
    UnmuteService.new.call(current_account, @target)
    head 204
  end

  private

  def set_target!
    @target = Account.find(params[:userId])
  rescue ActiveRecord::RecordNotFound
    render_error('No such user', 'NO_SUCH_USER', 404)
  end
end
