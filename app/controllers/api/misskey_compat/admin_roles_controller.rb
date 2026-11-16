# frozen_string_literal: true

class Api::MisskeyCompat::AdminRolesController < Api::MisskeyCompat::BaseController
  include Api::MisskeyCompat::AdminModerationAccess

  BOOLEAN_PARAMS = %i(isPublic isModerator isAdministrator isExplorable asBadge preserveAssignmentOnMoveAccount canEditMembersByModerator).freeze
  MODERATOR_PERMISSIONS = YAML.load_file(Rails.root.join('config', 'roles.yml')).dig('moderator', 'permissions').map(&:to_sym).freeze
  NO_SUCH_ROLE_IDS = {
    'show' => '07dc7d34-c0d8-49b7-96c6-db3ce64ee0b3',
    'users' => '224eff5e-2488-4b18-b3e7-f50d94421648',
    'update' => 'cd23ef55-09ad-428a-ac61-95a45e124b32',
    'destroy' => 'de0d6ecd-8e0a-4253-88ff-74bc89ae3d45',
    'assign' => '6503c040-6af4-4ed9-bf07-f2dd16678eab',
    'unassign' => '6e519036-a70d-4c76-b679-bc8fb18194e2',
  }.freeze
  NO_SUCH_USER_IDS = { 'assign' => '558ea170-f653-4700-94d0-5a818371d0df', 'unassign' => '2b730f78-1179-461b-88ad-d24c9af1a5ce' }.freeze
  MEMBER_ACCESS_DENIED_IDS = { 'assign' => '25b5bc31-dc79-4ebd-9bd2-c84978fd052c', 'unassign' => '24636eee-e8c1-493e-94b2-e16ad401e262' }.freeze

  misskey_admin_endpoint 'read:admin:roles', :index, :show, :users
  misskey_admin_endpoint 'write:admin:roles', :assign, :unassign
  misskey_admin_endpoint 'write:admin:roles', :create, :update, :destroy, :update_default_policies, administrator: true

  before_action :set_role, only: [:show, :users, :update, :destroy, :assign, :unassign]
  before_action :set_member, only: [:assign, :unassign]

  def index
    authorize :user_role, :index?
    roles = UserRole.assignable.reorder(position: :desc).to_a
    counts = User.where(role_id: roles.map(&:id)).group(:role_id).count
    render json: roles.map { |role| serialize_role(role, users_count: counts.fetch(role.id, 0)) }
  end

  def show
    authorize :user_role, :index?
    render json: serialize_role(@role)
  end

  def users
    authorize :user_role, :index?
    users = paginated_members.includes(:account).to_a
    assigned_at = Admin::ActionLog.where(target_type: 'User', target_id: users.map(&:id), action: 'change_role').group(:target_id).maximum(:created_at)
    serialized = misskey_detailed_users(users.map(&:account))

    render json: users.map { |user| { id: MisskeyCompat::MiId.encode(user.id), createdAt: (assigned_at[user.id] || user.created_at).iso8601, user: serialized[user.account_id], expiresAt: nil } }
  end

  def create
    authorize :user_role, :create?
    return render_invalid_param('#/properties/name', 'must be string') unless params[:name].is_a?(String)
    return unless valid_role_params?

    role = UserRole.new
    role.current_account = current_account
    apply_role_params(role)
    role.save!
    log_action :create, role
    render json: serialize_role(role)
  end

  def update
    authorize @role, :update?
    return render_invalid_param('#/properties/name', 'must be string') if params.key?(:name) && !params[:name].is_a?(String)
    return unless valid_role_params?

    @role.current_account = current_account
    apply_role_params(@role)
    @role.save!
    log_action :update, @role
    head 204
  end

  def destroy
    authorize @role, :destroy?
    @role.destroy!
    log_action :destroy, @role
    head 204
  end

  def assign
    return render_member_access_denied unless member_editable?
    return render_misskey_internal_error('User is already assigned to this role') if @member.role_id == @role.id

    expires_at = params[:expiresAt]
    return render_invalid_param('#/properties/expiresAt', 'must be integer') unless expires_at.nil? || expires_at.is_a?(Integer)
    return head 204 if expires_at.present? && expires_at <= (Time.now.to_f * 1000)
    return render_invalid_param('#/properties/expiresAt', 'role assignment expiry is not supported') if expires_at.present?

    change_member_role(@role)
  end

  def unassign
    return render_member_access_denied unless member_editable?
    return render_error('Not assigned', 'NOT_ASSIGNED', 400, id: 'b9060ac7-5c94-4da4-9f55-2047c953df44') unless @member.role_id == @role.id

    change_member_role(nil)
  end

  def update_default_policies
    policies = params[:policies]
    return render_invalid_param('#/properties/policies', 'must be object') unless policies.is_a?(ActionController::Parameters)

    everyone = UserRole.everyone
    authorize everyone, :update?
    quota = non_negative_integer(policies[:driveCapacityMb]) if policies.key?(:driveCapacityMb)

    if policies.key?(:driveCapacityMb)
      authorize :settings, :update?
      return render_invalid_param('#/properties/policies', 'driveCapacityMb must be a non-negative integer') if quota.nil?
    end

    if policies.key?(:canInvite)
      everyone.current_account = current_account
      everyone.permissions = policy_flag(everyone.permissions, :invite_users, policies[:canInvite] == true)
      everyone.save!
      log_action :update, everyone
    end

    Setting.drive_quota = quota unless quota.nil?
    head 204
  end

  private

  def base_policies
    @base_policies ||= MisskeyCompat::AdminRoleSerializer.base_policies(compat_policies)
  end

  def serialize_role(role, users_count: nil)
    MisskeyCompat::AdminRoleSerializer.serialize(role, base_policies:, users_count:)
  end

  def set_role
    @role = UserRole.find_by(id: params[:roleId])
    render_error('No such role', 'NO_SUCH_ROLE', 400, id: NO_SUCH_ROLE_IDS[action_name]) if @role.nil? || @role.everyone?
  end

  def set_member
    @member = Account.find_by(id: params[:userId])&.user
    render_error('No such user', 'NO_SUCH_USER', 400, id: NO_SUCH_USER_IDS[action_name]) if @member.nil?
  end

  def member_editable?
    UserPolicy.new(current_account, @member).change_role? && current_account.user_role.overrides?(@role)
  end

  def render_member_access_denied
    render_error('Only administrators can edit members of the role', 'ACCESS_DENIED', 400, id: MEMBER_ACCESS_DENIED_IDS[action_name])
  end

  def change_member_role(role)
    @member.current_account = current_account
    @member.update!(role: role)
    log_action :change_role, @member
    head 204
  end

  def paginated_members
    scope = @role.users
    scope = apply_compat_pagination_dates(scope)
    scope = scope.where(id: ...params[:untilId].to_i) if params[:untilId].present?
    scope = scope.where(User.arel_table[:id].gt(params[:sinceId].to_i)) if params[:sinceId].present?
    scope.reorder(id: forward_pagination? ? :asc : :desc).limit(pagination_limit(default: 10, max: 100))
  end

  def valid_role_params?
    param, reason = role_params_error
    return true if param.nil?

    render_invalid_param("#/properties/#{param}", reason)
    false
  end

  def role_params_error
    invalid = BOOLEAN_PARAMS.find { |key| params.key?(key) && params[key] != true && params[key] != false }
    return [invalid, 'must be boolean'] if invalid
    return [:target, 'conditional roles are not supported'] if params.key?(:target) && params[:target] != 'manual'
    return [:displayOrder, 'must be number'] if params.key?(:displayOrder) && !params[:displayOrder].is_a?(Numeric)
    return [:policies, 'must be object'] if params.key?(:policies) && !params[:policies].is_a?(ActionController::Parameters)
    return [:policies, 'driveCapacityMb must be a non-negative integer'] unless valid_drive_policy?(params[:policies])

    nil
  end

  def valid_drive_policy?(policies)
    drive = policies.is_a?(ActionController::Parameters) ? policies[:driveCapacityMb] : nil
    return true unless drive.is_a?(ActionController::Parameters) && drive[:useDefault] != true

    non_negative_integer(drive[:value]).present?
  end

  def non_negative_integer(value)
    integer = Integer(value, exception: false) if value.is_a?(Numeric) || value.is_a?(String)
    integer if integer&.>=(0)
  end

  def apply_role_params(role)
    role.name = params[:name] if params.key?(:name)
    role.color = params[:color].to_s if params.key?(:color)
    role.position = params[:displayOrder].to_i if params.key?(:displayOrder)
    role.highlighted = params[:asBadge] if params.key?(:asBadge)
    apply_role_flags(role)
    apply_role_policies(role, params[:policies]) if params[:policies].is_a?(ActionController::Parameters)
  end

  def apply_role_flags(role)
    if params.key?(:isModerator)
      moderation_bits = UserRole::Flags::CATEGORIES[:moderation].sum { |flag| UserRole::FLAGS[flag] }
      role.permissions &= ~moderation_bits
      role.permissions |= MODERATOR_PERMISSIONS.sum { |flag| UserRole::FLAGS[flag] } if params[:isModerator]
    end

    role.permissions = policy_flag(role.permissions, :administrator, params[:isAdministrator]) if params.key?(:isAdministrator)
  end

  def apply_role_policies(role, policies)
    MisskeyCompat::AdminRoleSerializer::FLAG_POLICIES.each do |key, flag|
      next unless policies[key].is_a?(ActionController::Parameters)

      role.permissions = policy_flag(role.permissions, flag, policies[key][:useDefault] != true && policies[key][:value] == true)
    end

    drive = policies[:driveCapacityMb]
    role.drive_quota = drive[:useDefault] == true ? nil : non_negative_integer(drive[:value]) if drive.is_a?(ActionController::Parameters)
  end

  def policy_flag(permissions, flag, enabled)
    enabled ? permissions | UserRole::FLAGS[flag] : permissions & ~UserRole::FLAGS[flag]
  end
end
