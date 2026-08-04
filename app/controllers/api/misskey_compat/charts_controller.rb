# frozen_string_literal: true

class Api::MisskeyCompat::ChartsController < Api::MisskeyCompat::BaseController
  before_action :require_drive_enabled!, only: [:drive, :user_drive]
  before_action :require_user!, only: %i(user_drive user_following user_notes user_pv user_reactions)
  requires_misskey_permission 'read:account', :user_drive, :user_following, :user_notes, :user_pv, :user_reactions

  def active_users
    render_chart(:active_users)
  end

  def ap_request
    render_chart(:ap_request)
  end

  def drive
    render_chart(:drive)
  end

  def federation
    render_chart(:federation)
  end

  def instance
    host = params[:host].to_s.downcase
    return render_invalid_param('#/properties/host', 'must be a non-empty string') if host.blank? || host.bytesize > 255

    render_chart(:instance, group: host)
  end

  def notes
    render_chart(:notes)
  end

  def user_drive
    render_user_chart(:user_drive)
  end

  def user_following
    render_user_chart(:user_following, suppressed: !follow_graph_exposed?)
  end

  def user_notes
    render_user_chart(:user_notes)
  end

  def user_pv
    render_user_chart(:user_pv)
  end

  def user_reactions
    render_user_chart(:user_reactions)
  end

  def users
    render_chart(:users)
  end

  private

  def render_user_chart(name, suppressed: false)
    account_id = params[:userId].to_s
    return render_invalid_param('#/properties/userId', 'must be a valid user id') unless account_id.match?(/\A[1-9]\d*\z/)
    return render_error('Access denied', 'PERMISSION_DENIED', 403) unless account_id.to_i == current_account.id

    render_chart(name, group: account_id.to_i, suppressed: suppressed)
  end

  def render_chart(name, group: nil, suppressed: false)
    return unless object_body!
    return if rate_limited?(:misskey_compat_api)

    chart = MisskeyCompat::ChartService.new(
      name: name,
      span: params[:span],
      limit: params[:limit],
      offset: params[:offset],
      group: group,
      suppressed: suppressed
    )
    render json: chart.call
  rescue MisskeyCompat::ChartService::InvalidParameter => e
    render_invalid_param(e.param, e.message)
  end

  def require_drive_enabled!
    render_error('This endpoint is not available', 'ENDPOINT_DISABLED', 404) unless Setting.drive_enabled
  end
end
