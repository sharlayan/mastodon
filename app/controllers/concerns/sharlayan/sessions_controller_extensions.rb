# frozen_string_literal: true

module Sharlayan::SessionsControllerExtensions
  extend ActiveSupport::Concern

  prepended do
    before_action :authenticate_user!, only: :switch_account
  end

  def switch_account
    handle_account_switch
  end

  def destroy
    parent_account = Account.find_by(id: switch_parent_stack.first)

    if parent_account&.user&.functional?
      switch_to_user(parent_account.user, [], parent_account.id)
      respond_to_account_return
      return
    end

    clear_switch_parent_stack
    super
  end

  protected

  def require_no_authentication
    super
  end

  private

  def continue_after?
    switch_parent_stack.blank? && super
  end

  def handle_account_switch
    unless user_signed_in?
      redirect_to new_user_session_path
      return
    end

    target_account = Account.find_by(id: params[:switch_to])
    target_user = target_account&.user

    unless target_user&.functional?
      redirect_to root_path, alert: I18n.t('account_switcher.switch_failed')
      return
    end

    new_stack = compute_switch_stack(switch_parent_stack, target_account)
    if new_stack.nil? || new_stack.length > 1
      redirect_to root_path, alert: I18n.t('account_switcher.switch_unauthorized')
      return
    end

    switch_to_user(target_user, new_stack, target_account.id)
    redirect_to root_path
  end

  def switch_to_user(target_user, new_stack, owner_id)
    sign_out(current_user)
    reset_session
    sign_in(target_user)
    persist_switch_parent_stack(new_stack, owner_id)
    target_user.update_sign_in!(new_sign_in: true)
  end

  def respond_to_account_return
    respond_to do |format|
      format.json { render json: { redirect_to: root_path }, status: 200 }
      format.any { redirect_to root_path }
    end
  end

  def compute_switch_stack(parent_stack, target_account)
    if parent_stack.present?
      root_account_id = parent_stack.first

      if root_account_id == target_account.id
        return unless AccountSwitchAuthorization.exists?(account_id: root_account_id, target_account_id: current_account.id)

        return []
      end

      return [root_account_id] if AccountSwitchAuthorization.exists?(account_id: root_account_id, target_account_id: target_account.id)

      return
    end

    [current_account.id] if current_account.account_switch_authorizations.exists?(target_account:)
  end

  def on_authentication_success(user, security_measure)
    disable_custom_css_if_requested(user)
    super
  end

  def disable_custom_css_if_requested(user)
    return unless ActiveModel::Type::Boolean.new.cast(params[:disable_css])

    user.settings['web.use_custom_css'] = false
    user.save
  end
end
