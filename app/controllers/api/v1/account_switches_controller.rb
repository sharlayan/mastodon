# frozen_string_literal: true

class Api::V1::AccountSwitchesController < Api::BaseController
  before_action -> { doorkeeper_authorize! :read, :'read:accounts' }, only: [:index]
  before_action -> { doorkeeper_authorize! :write, :'write:accounts' }, only: [:destroy]
  before_action :require_user!
  before_action :set_authorization, only: [:destroy]

  def index
    parent_stack = switch_parent_stack
    root_parent_id = parent_stack.first
    direct_parent_id = parent_stack.last

    # Always show the root (main) account's children, not the current sub-account's
    children_owner = (Account.find_by(id: root_parent_id) if root_parent_id.present?) || current_account

    children = children_owner.account_switch_authorizations
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

  def destroy
    @authorization.destroy!
    render_empty
  end

  private

  def set_authorization
    @authorization = current_account.account_switch_authorizations.find(params[:id])
  end
end
