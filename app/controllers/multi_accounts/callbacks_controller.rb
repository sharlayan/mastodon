# frozen_string_literal: true

class MultiAccounts::CallbacksController < ApplicationController
  skip_before_action :require_functional!

  layout 'auth'

  after_action :set_csp_nonce_directives

  def show
    @state = params[:state]
    @code = params[:code]
    @error = params[:error]
  end

  private

  def set_csp_nonce_directives
    request.content_security_policy_nonce_directives = %w(script-src)
  end
end
