# frozen_string_literal: true

class Api::MisskeyCompat::AdminInvitesController < Api::MisskeyCompat::BaseController
  include Api::MisskeyCompat::AdminModerationAccess

  TYPES = %w(unused used expired all).freeze
  SORTS = %w(+createdAt -createdAt +usedAt -usedAt).freeze
  CREATE_LIMIT = 100

  misskey_admin_endpoint 'write:admin:invite-codes', :create
  misskey_admin_endpoint 'read:admin:invite-codes', :index

  def index
    authorize :invite, :index?
    return render_invalid_param('#/properties/type', 'must be equal to one of the allowed values') unless params[:type].nil? || TYPES.include?(params[:type])
    return render_invalid_param('#/properties/sort', 'must be equal to one of the allowed values') unless params[:sort].nil? || SORTS.include?(params[:sort])

    offset = offset_param
    return if offset.nil?

    invites = sorted_invites(filtered_invites).includes(user: :account).limit(pagination_limit(default: 30, max: 100)).offset(offset).to_a
    render json: serialize_invites(invites)
  end

  def create
    authorize :invite, :create?
    count = params[:count].nil? ? 1 : params[:count]
    return render_invalid_param('#/properties/count', "must be an integer between 1 and #{CREATE_LIMIT}") unless count.is_a?(Integer) && count.between?(1, CREATE_LIMIT)

    expires_at = parse_expires_at
    return render_error('Invalid date-time format', 'INVALID_DATE_TIME', 400, id: 'f1380b15-3760-4c6c-a1db-5c3aaf1cbd49') if expires_at == :invalid

    invites = Invite.transaction do
      Array.new(count) { Invite.create!(user: current_user, max_uses: 1, expires_at: expires_at) }
    end
    render json: serialize_invites(invites)
  end

  private

  def parse_expires_at
    value = params[:expiresAt]
    return nil if value.nil?
    return :invalid unless value.is_a?(String)

    Time.zone.parse(value) || :invalid
  rescue ArgumentError
    :invalid
  end

  def filtered_invites
    case params[:type]
    when 'unused'
      Invite.where(uses: 0)
    when 'used'
      Invite.where(uses: 1..)
    when 'expired'
      Invite.where(expires_at: ...Time.now.utc)
    else
      Invite.all
    end
  end

  def sorted_invites(scope)
    case params[:sort]
    when '-createdAt'
      scope.order(id: :asc)
    when '+usedAt'
      scope.order(Arel.sql("(#{first_use_sql}) DESC NULLS LAST"))
    when '-usedAt'
      scope.order(Arel.sql("(#{first_use_sql}) ASC NULLS FIRST"))
    else
      scope.order(id: :desc)
    end
  end

  def first_use_sql
    'SELECT MIN(users.created_at) FROM users WHERE users.invite_id = invites.id'
  end

  def serialize_invites(invites)
    first_users = User.where(invite_id: invites.map(&:id)).includes(:account).order(created_at: :asc).group_by(&:invite_id).transform_values(&:first)

    invites.map do |invite|
      used_by = first_users[invite.id]

      {
        id: MisskeyCompat::MiId.encode(invite.id),
        code: invite.code,
        expiresAt: invite.expires_at&.iso8601,
        createdAt: invite.created_at.iso8601,
        createdBy: invite.user&.account && MisskeyCompat::UserSerializer.serialize(invite.user.account),
        usedBy: used_by && MisskeyCompat::UserSerializer.serialize(used_by.account),
        usedAt: used_by&.created_at&.iso8601,
        used: invite.uses.positive?,
      }
    end
  end
end
