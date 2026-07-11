# frozen_string_literal: true

class Api::MisskeyCompat::RolesController < Api::MisskeyCompat::BaseController
  def index
    render json: explorable_roles.map { |role| serialize_role(role) }
  end

  def show
    role = UserRole.find_by(id: params[:roleId])
    return render_error('No such role', 'NO_SUCH_ROLE', 404) if role.nil? || role.everyone? || role.nobody?

    render json: serialize_role(role)
  end

  def users
    role = UserRole.find_by(id: params[:roleId])
    return render_error('No such role', 'NO_SUCH_ROLE', 404) if role.nil? || role.everyone? || role.nobody?

    accounts = discoverable_members(role.id).order(id: :desc)
    accounts = accounts.where(accounts: { id: ...until_id.to_i }) if until_id.present?
    accounts = accounts.where(accounts: { id: (since_id.to_i + 1).. }) if since_id.present?
    accounts = accounts.limit(pagination_limit)

    render json: accounts.map { |account| { id: MisskeyCompat::MiId.encode(account.id), user: serialize_user(account) } }
  end

  private

  def explorable_roles
    role_ids = discoverable_members.distinct.pluck('users.role_id').compact
    return [] if role_ids.empty?

    UserRole.where(id: role_ids).where.not(id: UserRole::EVERYONE_ROLE_ID).order(position: :asc)
  end

  def discoverable_members(role_id = nil)
    scope = Account.local.where(discoverable: true, suspended_at: nil).joins(:user)
    scope = scope.where(users: { role_id: role_id }) if role_id
    scope
  end

  def serialize_role(role)
    {
      id: MisskeyCompat::MiId.encode(role.id),
      createdAt: role.created_at&.iso8601,
      updatedAt: role.updated_at&.iso8601,
      name: role.name,
      description: '',
      color: role.color.presence,
      iconUrl: nil,
      target: 'manual',
      condFormula: {},
      isPublic: true,
      isExplorable: true,
      asBadge: role.highlighted?,
      isModerator: role.can?(*UserRole::Flags::CATEGORIES[:moderation]),
      isAdministrator: role.can?(:administrator),
      canEditMembersByModerator: false,
      displayOrder: role.position,
      usersCount: discoverable_members(role.id).count,
    }
  end

  def serialize_user(account)
    MisskeyCompat::UserSerializer.serialize(account, viewer: current_account)
  end

  def until_id
    params[:untilId].presence
  end

  def since_id
    params[:sinceId].presence
  end
end
