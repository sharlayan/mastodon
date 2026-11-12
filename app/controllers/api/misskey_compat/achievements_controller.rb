# frozen_string_literal: true

class Api::MisskeyCompat::AchievementsController < Api::MisskeyCompat::BaseController
  requires_write_scope :claim
  requires_misskey_permission 'read:account', :index
  requires_misskey_permission 'write:account', :claim

  before_action :require_user!, only: :claim
  before_action :prohibit_moved_account!, only: :claim
  before_action :require_user_if_authenticated!, only: :index

  def index
    return render_invalid_param('#/properties/userId', 'must be a string') unless params[:userId].is_a?(String) && params[:userId].present?

    account = Account.without_requested_deletion.find_by(id: params[:userId])
    return render_error('No such user', 'NO_SUCH_USER', 404) if account.nil?

    render json: MisskeyAchievement.for_account(account).map(&:as_misskey_json)
  end

  def claim
    return render_invalid_param('#/properties/name', 'must be one of the achievement names') unless MisskeyAchievement::NAMES.include?(params[:name])

    MisskeyAchievement.unlock!(current_account, params[:name])
    head 204
  end
end
