# frozen_string_literal: true

class Api::MisskeyCompat::InvitesController < Api::MisskeyCompat::BaseController
  # rubocop:disable-next I18n/RailsI18n/DecorateString
  ERRORS = {
    no_such_code: ['No such invite code.', 'NO_SUCH_INVITE_CODE', 404, 'cd4f9ae4-7854-4e3e-8df9-c296f051e634'],
    access_denied: ['Access denied.', 'ACCESS_DENIED', 400, '5eb8d909-2540-4970-90b8-dd6f86088121'],
    cant_delete: ["You can't delete this invite code.", 'CAN_NOT_DELETE_INVITE_CODE', 400, 'ff17af39-000c-4d4e-abdf-848fa30fc1ce'],
    role_permission_denied: ['You are not assigned to a required role.', 'ROLE_PERMISSION_DENIED', 403, '7f86f06f-7e15-4057-8561-f4b6d4ac755a'],
  }.freeze

  requires_write_scope :create, :destroy
  requires_misskey_permission 'read:invite-codes', :index, :limit
  requires_misskey_permission 'write:invite-codes', :create, :destroy

  before_action :require_user!
  before_action :require_invite_role!

  def index
    scope = apply_compat_pagination_dates(current_user.invites.includes(user: :account, users: :account))
    scope = scope.where(id: ...params[:untilId].to_i) if params[:untilId].present?
    scope = scope.where('invites.id > ?', params[:sinceId].to_i) if params[:sinceId].present?
    invites = scope.reorder(id: forward_pagination? ? :asc : :desc).limit(pagination_limit(default: 30, max: 100))

    render json: invites.map { |invite| serialize(invite) }
  end

  def limit
    render json: { remaining: nil }
  end

  def create
    authorize :invite, :create?

    invite = Invite.create!(user: current_user, max_uses: 1)
    render json: serialize(invite)
  end

  def destroy
    return render_invalid_param('#/properties/inviteId', 'is required') unless params.key?(:inviteId)

    invite = Invite.find_by(id: params[:inviteId].to_s) if compat_id?(params[:inviteId])
    return render_invite_error(:no_such_code) if invite.nil?
    return render_invite_error(:access_denied) unless InvitePolicy.new(current_account, invite).destroy?
    return render_invite_error(:cant_delete) if invite.uses.positive? && !moderator?

    invite.expire!
    head 204
  end

  private

  def require_invite_role!
    return if current_user.nil? || current_user.can?(:invite_users) || (action_name == 'destroy' && moderator?)

    render_invite_error(:role_permission_denied, kind: 'permission')
  end

  def render_invite_error(key, kind: 'client')
    message, code, status, id = ERRORS.fetch(key)
    render_error(message, code, status, id:, kind:)
  end

  def moderator?
    current_user.can?(:manage_invites)
  end

  def serialize(invite)
    first_user = invite.users.min_by(&:id)

    {
      id: MisskeyCompat::MiId.encode(invite.id),
      code: invite.code,
      expiresAt: invite.expires_at&.iso8601(3),
      createdAt: invite.created_at.iso8601(3),
      createdBy: invite.user&.account && MisskeyCompat::UserSerializer.serialize(invite.user.account),
      usedBy: first_user&.account && MisskeyCompat::UserSerializer.serialize(first_user.account),
      usedAt: first_user&.created_at&.iso8601(3),
      used: invite.uses.positive?,
    }
  end
end
