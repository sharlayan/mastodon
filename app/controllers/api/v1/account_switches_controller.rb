# frozen_string_literal: true

class Api::V1::AccountSwitchesController < Api::BaseController
  before_action -> { doorkeeper_authorize! :read, :'read:accounts' }, only: [:index]
  before_action -> { doorkeeper_authorize! :write, :'write:accounts' }, only: [:destroy]
  before_action :require_user!
  before_action :set_authorization, only: [:destroy]

  def index
    children = current_account.account_switch_authorizations
      .includes(target_account: [:account_stat])
      .order(created_at: :desc)

    parent_stack = session.fetch(:switch_parent_stack, []).map(&:to_i)
    parent_account_id = parent_stack.last

    parent_account = if parent_account_id.present?
                       auth = AccountSwitchAuthorization.find_by(
                         account_id: parent_account_id,
                         target_account_id: current_account.id
                       )
                       auth.present? ? Account.includes(:account_stat).find_by(id: parent_account_id) : nil
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
