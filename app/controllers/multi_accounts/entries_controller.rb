# frozen_string_literal: true

class MultiAccounts::EntriesController < ApplicationController
  before_action :authenticate_user!
  before_action :require_server_stored_account_switching!, unless: -> { params[:reauthenticate_account_id].present? }

  def show
    state = SecureRandom.hex(32)
    nonce = SecureRandom.uuid
    reauthenticate_account_id = permitted_reauthentication_account_id

    MultiAccounts::StateStore.store!(state, nonce, current_user.id, switch_parent_stack: switch_parent_stack, session_id: session_binding_id, reauthenticate_account_id: reauthenticate_account_id)

    render json: {
      authorize_url: multi_accounts_auth_sign_in_url(state: state),
      state: state,
      nonce: nonce,
    }
  end

  private

  def require_server_stored_account_switching!
    head 404 unless Setting.server_stored_account_switching_enabled
  end

  def permitted_reauthentication_account_id
    requested_id = params[:reauthenticate_account_id]
    return if requested_id.blank?

    owner = Account.find_by(id: switch_parent_stack.first) || current_account
    owner.account_switch_authorizations.find_by!(target_account_id: requested_id).target_account_id
  end

  def session_binding_id
    session.id&.public_id
  end
end
