# frozen_string_literal: true

class Api::V1::AccountSwitchesController < Api::BaseController
  include RoutingHelper

  before_action -> { doorkeeper_authorize! :read, :'read:accounts' }, only: [:index, :linked_notifications]
  before_action -> { doorkeeper_authorize! :write, :'write:accounts' }, only: [:destroy, :create_push_forward, :destroy_push_forward]
  before_action :require_user!
  before_action :set_authorization, only: [:destroy]
  before_action :set_push_forward_auth, only: [:destroy_push_forward]

  def index
    parent_stack = switch_parent_stack
    root_parent_id = parent_stack.first
    direct_parent_id = parent_stack.last

    # Always show the root (main) account's children, not the current sub-account's
    children_owner = (Account.find_by(id: root_parent_id) if root_parent_id.present?) || current_account

    children = children_owner.account_switch_authorizations
      .where.not(target_account_id: current_account.id)
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
    }
  end

  def linked_notifications
    parent_stack   = switch_parent_stack
    root_parent_id = parent_stack.first
    children_owner = (Account.find_by(id: root_parent_id) if root_parent_id.present?) || current_account

    children = children_owner.account_switch_authorizations
      .where.not(target_account_id: current_account.id)
      .includes(:target_account)

    since_ids = params[:since_ids]&.to_unsafe_h || {}

    results = []

    children.each do |auth|
      linked_account = auth.target_account
      next unless linked_account&.user

      scope = Notification.where(account_id: linked_account.id).includes(:from_account)
      since_id = since_ids[linked_account.id.to_s].presence
      scope = scope.where(id: (since_id.to_i + 1)..) if since_id

      scope.order(id: :desc).limit(5).each do |notification|
        next unless notification.from_account

        results << {
          linked_account_id: linked_account.id.to_s,
          linked_account_acct: linked_account.acct,
          notification: {
            id: notification.id.to_s,
            type: notification.type,
            created_at: notification.created_at.iso8601,
            account: {
              id: notification.from_account.id.to_s,
              acct: notification.from_account.acct,
              display_name: notification.from_account.display_name,
              username: notification.from_account.username,
              avatar: full_asset_url(notification.from_account.avatar_static_url),
            },
          },
        }
      end
    end

    results.sort_by! { |r| -r[:notification][:id].to_i }

    render json: results
  end

  def create_push_forward
    auth = find_linked_authorization
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

  private

  def set_authorization
    @authorization = current_account.account_switch_authorizations.find(params[:id])
  end

  def find_linked_authorization
    parent_stack   = switch_parent_stack
    root_parent_id = parent_stack.first
    children_owner = (Account.find_by(id: root_parent_id) if root_parent_id.present?) || current_account

    children_owner.account_switch_authorizations
      .where(target_account_id: params[:linked_account_id])
      .where.not(target_account_id: current_account.id)
      .first
  end

  def set_push_forward_auth
    @push_forward_auth = find_linked_authorization
    render json: { error: 'Not found' }, status: 404 unless @push_forward_auth
  end
end
