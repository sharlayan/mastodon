# frozen_string_literal: true

class MultiAccounts::AuthController < ApplicationController
  skip_before_action :require_functional!

  layout 'auth'

  before_action :validate_state
  after_action :set_csp_nonce_directives, only: %i(create verify_otp)

  def new
    @user = User.new
  end

  def create
    @user = User.new(email: auth_params[:email])
    user = User.find_for_authentication(email: auth_params[:email])

    if user.nil? || !user.valid_password?(auth_params[:password])
      flash.now[:alert] = I18n.t('devise.failure.invalid', authentication_keys: User.authentication_keys.join('/'))
      render :new
      return
    end

    unless user.functional?
      flash.now[:alert] = I18n.t("devise.failure.#{user.inactive_message}")
      render :new
      return
    end

    if user.otp_required_for_login?
      MultiAccounts::StateStore.update!(@state, authenticated_user_id: user.id)
      render :two_factor
      return
    end

    complete_authentication(user)
  end

  def verify_otp
    state_data = MultiAccounts::StateStore.fetch(@state)

    unless state_data&.dig(:authenticated_user_id)
      flash.now[:alert] = I18n.t('devise.failure.timeout')
      @user = User.new
      render :new
      return
    end

    user = User.find_by(id: state_data[:authenticated_user_id])

    unless user&.functional?
      flash.now[:alert] = I18n.t('devise.failure.timeout')
      @user = User.new
      render :new
      return
    end

    otp = params[:user][:otp_attempt]

    if user.validate_and_consume_otp!(otp) || user.invalidate_otp_backup_code!(otp)
      complete_authentication(user)
    else
      flash.now[:alert] = I18n.t('users.invalid_otp_token')
      render :two_factor
    end
  end

  private

  def set_csp_nonce_directives
    request.content_security_policy_nonce_directives = %w(script-src style-src)
  end

  def auth_params
    params.expect(user: [:email, :password])
  end

  def validate_state
    @state = params[:state]
    @state_data = MultiAccounts::StateStore.fetch(@state)

    if @state_data.nil?
      render plain: I18n.t('devise.failure.timeout'), status: 400
      return
    end

    bound_session_id = @state_data[:session_id]
    if bound_session_id.present? && bound_session_id != session.id&.public_id
      render plain: I18n.t('devise.failure.timeout'), status: 400
      nil
    end
  end

  def complete_authentication(user)
    target_account = user.account
    source_user = User.find_by(id: @state_data[:user_id])

    unless source_user&.functional? && user.functional?
      render plain: I18n.t('devise.failure.timeout'), status: 400
      return
    end

    source_account = source_user.account

    # If the OAuth flow was initiated while a sub-account was active, resolve the root account
    parent_stack = Array(@state_data[:switch_parent_stack])
    root_parent_id = parent_stack.first
    if root_parent_id.present?
      root_account = Account.find_by(id: root_parent_id)
      unless root_account&.user&.functional?
        render plain: I18n.t('devise.failure.timeout'), status: 400
        return
      end

      source_account = root_account
    end

    if target_account.id == source_account.id
      flash.now[:alert] = I18n.t('multi_accounts.auth.same_account')
      @user = User.new
      render :new
      return
    end

    AccountSwitchAuthorization.find_or_create_by!(
      account: source_account,
      target_account: target_account
    )

    MultiAccounts::StateStore.consume!(@state, @state_data[:nonce])

    @result_state = @state
    render :success
  end
end
