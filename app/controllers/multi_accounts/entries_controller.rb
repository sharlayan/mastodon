# frozen_string_literal: true

class MultiAccounts::EntriesController < ApplicationController
  before_action :authenticate_user!

  def show
    state = SecureRandom.hex(32)
    nonce = SecureRandom.uuid

    MultiAccounts::StateStore.store!(state, nonce, current_user.id)

    render json: {
      authorize_url: multi_accounts_auth_sign_in_url(state: state),
      state: state,
      nonce: nonce,
    }
  end
end
