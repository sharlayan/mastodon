# frozen_string_literal: true

class Api::V1::AccountSwitchesController < Api::BaseController
  include RoutingHelper
  include Sharlayan::AccountSwitchDeviceConcern

  UNREAD_COUNT_LIMIT = 100
  LINKED_UNREAD_COUNTS_SQL = <<~SQL.squish.freeze
    WITH linked_accounts(account_id, last_read_id) AS (
      SELECT * FROM UNNEST(ARRAY[:account_ids]::bigint[], ARRAY[:last_read_ids]::bigint[])
    )
    SELECT linked_accounts.account_id, COUNT(unread_notifications.id)
    FROM linked_accounts
    CROSS JOIN LATERAL (
      SELECT notifications.id
      FROM notifications
      INNER JOIN accounts from_accounts ON from_accounts.id = notifications.from_account_id
      WHERE notifications.account_id = linked_accounts.account_id
        AND notifications.id > linked_accounts.last_read_id
        AND notifications.filtered = FALSE
        AND from_accounts.suspended_at IS NULL
        AND from_accounts.requested_deletion_at IS NULL
      ORDER BY notifications.id DESC
      LIMIT :limit
    ) unread_notifications
    GROUP BY linked_accounts.account_id
  SQL

  before_action -> { doorkeeper_authorize! :read, :'read:accounts' }, only: [:index, :linked_unread_counts]
  before_action -> { doorkeeper_authorize! :write, :'write:accounts' }, only: [:destroy, :destroy_inbound, :create_push_forward, :destroy_push_forward]
  before_action :require_user!
  before_action :require_root_account, only: [:destroy]
  before_action :set_authorization, only: [:destroy]
  before_action :set_inbound_authorization, only: [:destroy_inbound]
  before_action :require_inactive_inbound_authorization, only: [:destroy_inbound]
  before_action :set_push_forward_auth, only: [:destroy_push_forward]

  def index
    parent_stack = switch_parent_stack
    direct_parent_id = parent_stack.last

    children_owner = resolve_children_owner

    exclude_ids = [current_account.id, children_owner.id].uniq
    children = children_owner.account_switch_authorizations
      .where.not(target_account_id: exclude_ids)
      .includes(target_account: [:account_stat])
      .order(created_at: :desc)

    parent_account = if direct_parent_id.present?
                       auth = AccountSwitchAuthorization.find_by(
                         account_id: direct_parent_id,
                         target_account_id: current_account.id
                       )
                       auth.present? ? Account.includes(:account_stat).find_by(id: direct_parent_id) : nil
                     end

    serialized_children = ActiveModelSerializers::SerializableResource.new(
      children,
      each_serializer: REST::AccountSwitchAuthorizationSerializer,
      scope: current_user,
      scope_name: :current_user
    ).as_json
    child_authorization_state = children.index_by { |authorization| authorization.id.to_s }
    serialized_children.each do |serialized|
      authorization = child_authorization_state.fetch(serialized[:id].to_s)
      device = find_or_record_account_switch_device(authorization.target_account, trust: legacy_account_switch_session?)
      AccountSwitchDeviceApproval.request!(account: children_owner, target_account: authorization.target_account, account_switch_device: device, request_ip: request.remote_ip) unless device.trusted?
      serialized[:session_authorized] = device.trusted?
      serialized[:session_approval_pending] = AccountSwitchDeviceApproval.pending.exists?(account: children_owner, target_account: authorization.target_account, account_switch_device: device)
    end

    render json: {
      root_account_id: children_owner.id.to_s,
      parent: parent_account && ActiveModelSerializers::SerializableResource.new(
        parent_account,
        serializer: REST::AccountSerializer,
        scope: current_user,
        scope_name: :current_user
      ).as_json,
      children: serialized_children,
      inbound: inbound_authorizations,
    }
  end

  def linked_unread_counts
    children_owner = resolve_children_owner
    device_digest = account_switch_device_digest

    auths = children_owner.account_switch_authorizations
      .where.not(target_account_id: current_account.id)
      .joins('INNER JOIN account_switch_devices ON account_switch_devices.account_id = account_switch_authorizations.target_account_id')
      .where(account_switch_devices: { token_digest: device_digest, revoked_at: nil })
      .where.not(account_switch_devices: { trusted_at: nil })
      .includes(target_account: { user: :markers })

    render json: linked_unread_counts_for(auths)
  end

  def create_push_forward
    auth = find_linked_authorization

    if auth.nil?
      owner = resolve_children_owner
      if params[:linked_account_id].to_s == owner.id.to_s
        auth = owner.account_switch_authorizations.create!(target_account_id: owner.id, push_forward: true)
        return render json: { id: auth.id.to_s }, status: 200
      end
    end

    return render json: { error: 'Not found' }, status: 404 unless auth

    auth.update!(push_forward: true)
    render json: { id: auth.id.to_s }, status: 200
  end

  def destroy_push_forward
    @push_forward_auth.update!(push_forward: false)
    render_empty
  end

  def destroy
    @authorization.destroy!
    render_empty
  end

  def destroy_inbound
    @inbound_authorization.destroy!
    clear_switch_parent_stack
    render_empty
  end

  private

  def linked_unread_counts_for(authorizations)
    pairs = authorizations.filter_map do |authorization|
      account = authorization.target_account
      next unless account&.user

      marker = account.user.markers.find { |item| item.timeline == 'notifications' }
      [account.id, marker&.last_read_id.to_i]
    end
    return {} if pairs.empty?

    query = Notification.sanitize_sql_array([LINKED_UNREAD_COUNTS_SQL,
                                             { account_ids: pairs.map(&:first), last_read_ids: pairs.map(&:last), limit: UNREAD_COUNT_LIMIT }])
    rows = Notification.connection.select_rows(query)

    pairs.to_h { |account_id, _| [account_id.to_s, 0] }.merge(rows.to_h { |account_id, count| [account_id.to_s, count.to_i] })
  end

  def require_root_account
    render json: { error: 'Cannot unlink accounts while switched into a linked account' }, status: 403 if switch_parent_stack.present?
  end

  def require_inactive_inbound_authorization
    active_parent_id = switch_parent_stack.first
    render json: { error: 'Cannot unlink the active parent while switched into a linked account' }, status: 403 if active_parent_id == @inbound_authorization.account_id
  end

  def resolve_children_owner
    parent_stack   = switch_parent_stack
    root_parent_id = parent_stack.first
    (Account.find_by(id: root_parent_id) if root_parent_id.present?) || current_account
  end

  def set_authorization
    @authorization = current_account.account_switch_authorizations.find(params[:id])
  end

  def set_inbound_authorization
    @inbound_authorization = AccountSwitchAuthorization.find_by!(id: params[:id], target_account: current_account)
  end

  def inbound_authorizations
    AccountSwitchAuthorization.where(target_account: current_account)
      .where.not(account: current_account)
      .includes(account: [:account_stat])
      .order(created_at: :desc)
      .map do |authorization|
        {
          id: authorization.id.to_s,
          created_at: authorization.created_at,
          account: ActiveModelSerializers::SerializableResource.new(
            authorization.account,
            serializer: REST::AccountSerializer,
            scope: current_user,
            scope_name: :current_user
          ).as_json,
        }
      end
  end

  def find_linked_authorization
    resolve_children_owner.account_switch_authorizations
      .find_by(target_account_id: params[:linked_account_id])
  end

  def set_push_forward_auth
    @push_forward_auth = find_linked_authorization
    render json: { error: 'Not found' }, status: 404 unless @push_forward_auth
  end
end
