# frozen_string_literal: true

class Api::MisskeyCompat::AdminModerationLogsController < Api::MisskeyCompat::BaseController
  include Api::MisskeyCompat::AdminModerationAccess

  LOG_TYPES = {
    'suspend' => %w(suspend Account),
    'unsuspend' => %w(unsuspend Account),
    'resetPassword' => %w(reset_password User),
    'unsetMfa' => %w(disable_2fa User),
    'unsetUserAvatar' => %w(remove_avatar User),
    'unsetUserBanner' => %w(remove_header User),
    'resolveAbuseReport' => %w(resolve Report),
    'createRole' => %w(create UserRole),
    'updateRole' => %w(update UserRole),
    'deleteRole' => %w(destroy UserRole),
  }.freeze
  TYPE_BY_ACTION = LOG_TYPES.invert.freeze

  misskey_admin_endpoint 'read:admin:show-moderation-log', :index, administrator: true

  def index
    authorize :audit_log, :index?
    return render json: [] if params[:type].present? && !LOG_TYPES.key?(params[:type])

    logs = paginated_logs.includes(:account, :target).to_a
    users = misskey_detailed_users(logs.map(&:account))
    @resolutions = MisskeyAbuseReportResolution.where(report_id: logs.select { |log| log.target_type == 'Report' }.map(&:target_id)).pluck(:report_id, :resolved_as).to_h

    render json: logs.map { |log| serialize_log(log, users[log.account_id]) }
  end

  private

  def paginated_logs
    scope = Admin::ActionLog.where(log_conditions)
    scope = scope.where(account_id: params[:userId]) if params[:userId].present?
    scope = scope.where('admin_action_logs.human_identifier ILIKE ?', "%#{Admin::ActionLog.sanitize_sql_like(params[:search])}%") if params[:search].is_a?(String) && params[:search].present?
    scope = apply_compat_pagination_dates(scope)
    scope = scope.where(id: ...params[:untilId].to_i) if params[:untilId].present?
    scope = scope.where(Admin::ActionLog.arel_table[:id].gt(params[:sinceId].to_i)) if params[:sinceId].present?
    scope.order(id: forward_pagination? ? :asc : :desc).limit(pagination_limit(default: 10, max: 100))
  end

  def log_conditions
    pairs = params[:type].present? ? [LOG_TYPES[params[:type]]] : LOG_TYPES.values
    table = Admin::ActionLog.arel_table
    pairs.map { |action, target_type| table[:action].eq(action).and(table[:target_type].eq(target_type)) }.reduce(:or)
  end

  def serialize_log(log, user)
    type = TYPE_BY_ACTION[[log.action.to_s, log.target_type]]

    {
      id: MisskeyCompat::MiId.encode(log.id),
      createdAt: log.created_at.iso8601,
      type: type,
      info: log_info(type, log),
      userId: MisskeyCompat::MiId.encode(log.account_id),
      user: user,
    }
  end

  def log_info(type, log)
    case log.target_type
    when 'Account', 'User'
      target_user_info(log)
    when 'Report'
      { reportId: MisskeyCompat::MiId.encode(log.target_id), resolvedAs: @resolutions[log.target_id] }
    when 'UserRole'
      role_info(type, log)
    end
  end

  def target_user_info(log)
    account = log.target.is_a?(User) ? log.target.account : log.target
    return misskey_user_log_info(account) if account.is_a?(Account)

    username, host = log.human_identifier.to_s.split('@', 2)
    { userId: nil, userUsername: username, userHost: host }
  end

  def role_info(type, log)
    role = log.target.is_a?(UserRole) ? MisskeyCompat::AdminRoleSerializer.serialize(log.target, base_policies: role_base_policies) : { id: MisskeyCompat::MiId.encode(log.target_id), name: log.human_identifier }
    info = { roleId: MisskeyCompat::MiId.encode(log.target_id) }
    type == 'updateRole' ? info.merge(before: role, after: role) : info.merge(role: role)
  end

  def role_base_policies
    @role_base_policies ||= MisskeyCompat::AdminRoleSerializer.base_policies(compat_policies)
  end
end
