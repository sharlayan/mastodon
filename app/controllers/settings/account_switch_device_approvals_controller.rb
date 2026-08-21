# frozen_string_literal: true

class Settings::AccountSwitchDeviceApprovalsController < Settings::BaseController
  include Sharlayan::AccountSwitchDeviceConcern

  before_action :set_current_device

  def index
    linked_accounts_owner = Account.find_by(id: switch_parent_stack.first) || current_account
    @linked_account_devices = AccountSwitchDevice.trusted
      .where(token_digest: account_switch_device_digest)
      .where(account_id: linked_accounts_owner.account_switch_authorizations.select(:target_account_id))
      .where.not(account_id: linked_accounts_owner.id)
      .includes(account: :account_stat)
      .order(last_seen_at: :desc)
    @linking_accounts = AccountSwitchAuthorization
      .where(target_account: current_account)
      .where.not(account: current_account)
      .includes(account: :account_stat)
      .order(created_at: :desc)
    @approvals = if @current_device.trusted?
                   current_account.incoming_account_switch_device_approvals.pending.includes(:account, :account_switch_device).order(created_at: :desc)
                 else
                   AccountSwitchDeviceApproval.none
                 end
    @trusted_devices = @current_device.trusted? ? current_account.account_switch_devices.trusted.order(last_seen_at: :desc) : AccountSwitchDevice.none
  end

  def approve
    return redirect_untrusted unless @current_device.trusted?

    approval = current_account.incoming_account_switch_device_approvals.pending.find(params[:id])
    if approval.account_switch_device_id == @current_device.id
      redirect_to settings_account_switch_device_approvals_path, alert: I18n.t('account_switch_devices.self_approval')
      return
    end

    approval.approve!(@current_device)
    redirect_to settings_account_switch_device_approvals_path, notice: I18n.t('account_switch_devices.approved')
  end

  def deny
    return redirect_untrusted unless @current_device.trusted?

    current_account.incoming_account_switch_device_approvals.pending.find(params[:id]).deny!(@current_device)
    redirect_to settings_account_switch_device_approvals_path, notice: I18n.t('account_switch_devices.denied')
  end

  def destroy_device
    return redirect_untrusted unless @current_device.trusted?

    device = current_account.account_switch_devices.trusted.find(params[:id])
    if device.id == @current_device.id
      redirect_to settings_account_switch_device_approvals_path, alert: I18n.t('account_switch_devices.current_device_revoke')
      return
    end

    device.revoke!
    redirect_to settings_account_switch_device_approvals_path, notice: I18n.t('account_switch_devices.revoked')
  end

  helper_method :account_switch_device_label, :masked_account_switch_ip

  private

  def set_current_device
    @current_device = find_or_record_account_switch_device(current_account, trust: legacy_account_switch_session?)
  end

  def redirect_untrusted
    redirect_to settings_account_switch_device_approvals_path, alert: I18n.t('account_switch_devices.untrusted')
  end
end
