# frozen_string_literal: true

class Api::MisskeyCompat::SigninHistoryController < Api::MisskeyCompat::BaseController
  requires_misskey_permission 'read:account', :index

  before_action :require_user!
  before_action :require_native_user_token!

  def index
    render json: paginated_activities.map { |activity| serialize(activity) }
  end

  private

  def paginated_activities
    table = LoginActivity.arel_table
    scope = current_user.login_activities
    scope = scope.where(table[:id].lt(params[:untilId])) if params[:untilId].present?
    scope = scope.where(table[:id].gt(params[:sinceId])) if params[:sinceId].present?
    scope = apply_compat_pagination_dates(scope)
    scope.reorder(id: forward_pagination? ? :asc : :desc).limit(pagination_limit(default: 10, max: 100))
  end

  def serialize(activity)
    {
      id: MisskeyCompat::MiId.encode(activity.id),
      createdAt: activity.created_at&.iso8601,
      ip: activity.ip.to_s,
      headers: { 'user-agent' => activity.user_agent }.compact,
      success: activity.success || false,
    }
  end
end
