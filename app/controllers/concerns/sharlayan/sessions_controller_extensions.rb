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
    clear_switch_parent_stack
    super
  end

  protected

  def require_no_authentication
    super
  end

  private

  def handle_account_switch
    unless user_signed_in?
      redirect_to new_user_session_path
      return
    end

    target_account = Account.find_by(id: params[:switch_to])
    target_user = target_account&.user

    unless target_user&.active_for_authentication?
      redirect_to root_path, alert: I18n.t('account_switcher.switch_failed')
      return
    end

    new_stack = compute_switch_stack(switch_parent_stack, target_account)
    if new_stack.nil? || new_stack.length > 1
      redirect_to root_path, alert: I18n.t('account_switcher.switch_unauthorized')
      return
    end

    sign_out(current_user)
    sign_in(target_user)
    persist_switch_parent_stack(new_stack, target_account.id)
    target_user.update_sign_in!(new_sign_in: true)
    redirect_to root_path
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
