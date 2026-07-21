# frozen_string_literal: true

class Api::V1::AccountSwitchesController < Api::BaseController
  include RoutingHelper

  before_action -> { doorkeeper_authorize! :read, :'read:accounts' }, only: [:index, :linked_unread_counts]
  before_action -> { doorkeeper_authorize! :write, :'write:accounts' }, only: [:destroy, :destroy_inbound, :create_push_forward, :destroy_push_forward]
  before_action :require_user!
  before_action :set_authorization, only: [:destroy]
  before_action :set_inbound_authorization, only: [:destroy_inbound]
  before_action :set_push_forward_auth, only: [:destroy_push_forward]

  def index
    parent_stack = switch_parent_stack
    direct_parent_id = parent_stack.last

    children_owner = resolve_children_owner

    # Exclude current account and self-referential (main→main) from children list
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

    render json: {
      root_account_id: children_owner.id.to_s,
      parent: parent_account && ActiveModelSerializers::SerializableResource.new(
        parent_account,
        serializer: REST::AccountSerializer,
        scope: current_user,
        scope_name: :current_user
      ).as_json,
      children: ActiveModelSerializers::SerializableResource.new(
        children,
        each_serializer: REST::AccountSwitchAuthorizationSerializer,
        scope: current_user,
        scope_name: :current_user
      ).as_json,
      inbound: inbound_authorizations,
    }
  end

  def linked_unread_counts
    children_owner = resolve_children_owner

    auths = children_owner.account_switch_authorizations
      .where.not(target_account_id: current_account.id)
      .includes(target_account: { user: :markers })

    counts = {}

    auths.each do |auth|
      acct = auth.target_account
      next unless acct&.user

      marker = acct.user.markers.find { |m| m.timeline == 'notifications' }
      last_read_id = marker&.last_read_id&.positive? ? marker.last_read_id : nil
      scope = Notification.where(account_id: acct.id).without_suspended.where(filtered: false)
      scope = scope.where(id: ((last_read_id + 1)..)) if last_read_id
      counts[acct.id.to_s] = [scope.count, 100].min
    end

    render json: counts
  end

  def create_push_forward
    auth = find_linked_authorization

    # Auto-create self-referential auth for main account's own push forwarding
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
