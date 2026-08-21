# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Linked account session approvals' do
  let(:parent_user) { Fabricate(:user) }
  let(:target_user) { Fabricate(:user) }
  let(:authorization) { Fabricate(:account_switch_authorization, account: parent_user.account, target_account: target_user.account) }
  let(:current_device) { target_user.account.account_switch_devices.where.not(id: request_device.id).first! }
  let!(:request_device) { AccountSwitchDevice.create!(account: target_user.account, token_digest: 'request', first_seen_at: Time.current, last_seen_at: Time.current) }
  let!(:approval) do
    authorization
    AccountSwitchDeviceApproval.create!(account: parent_user.account, target_account: target_user.account, account_switch_device: request_device, expires_at: 10.minutes.from_now)
  end

  before do
    sign_in target_user
    get settings_account_switch_device_approvals_path
    current_device.update!(trusted_at: Time.current)
  end

  it 'lets the target account approve only its own pending request' do
    post approve_settings_account_switch_device_approval_path(approval)

    expect(response).to redirect_to(settings_account_switch_device_approvals_path)
    expect(request_device.reload).to be_trusted
    expect(approval.reload.approved_by_device).to eq(current_device)
  end

  it 'does not let another account approve the request' do
    sign_out target_user
    sign_in parent_user

    post approve_settings_account_switch_device_approval_path(approval)

    expect(response).to redirect_to(settings_account_switch_device_approvals_path)
    expect(request_device.reload).to_not be_trusted
  end

  it 'revokes the active switched session and its access token with the device' do
    switched_session = Fabricate(:session_activation, user: target_user)
    access_token = switched_session.access_token
    request_device.update!(trusted_at: Time.current, session_activation: switched_session)

    delete settings_account_switch_device_path(request_device)

    expect(request_device.reload).to_not be_trusted
    expect(SessionActivation.exists?(switched_session.id)).to be false
    expect(Doorkeeper::AccessToken.exists?(access_token.id)).to be false
  end

  it 'reuses one approval row when an expired request is renewed' do
    approval.update!(expires_at: 1.minute.ago)

    expect do
      AccountSwitchDeviceApproval.request!(account: parent_user.account, target_account: target_user.account, account_switch_device: request_device, request_ip: '192.0.2.1')
    end.to_not change(AccountSwitchDeviceApproval, :count)

    expect(approval.reload).to be_pending
    expect(approval.request_ip.to_s).to eq('192.0.2.1')
  end

  it 'lists accounts that have linked the current account' do
    get settings_account_switch_device_approvals_path

    expect(response.body).to include(I18n.t('account_switch_devices.linking_accounts'))
    expect(response.body).to include(parent_user.account.pretty_acct)
  end

  it 'lists only linked accounts authorized for the current browser session' do
    sign_out target_user
    sign_in parent_user
    get settings_account_switch_device_approvals_path
    parent_device = parent_user.account.account_switch_devices.order(:created_at).last!
    target_device = target_user.account.account_switch_devices.find_or_initialize_by(token_digest: parent_device.token_digest)
    target_device.update!(
      trusted_at: Time.current,
      revoked_at: nil,
      first_seen_at: Time.current,
      last_seen_at: Time.current,
      last_seen_ip: '192.0.2.1',
      user_agent: 'Mozilla/5.0 Chrome/120.0.0.0 Safari/537.36'
    )
    other_target = Fabricate(:user)
    Fabricate(:account_switch_authorization, account: parent_user.account, target_account: other_target.account)
    AccountSwitchDevice.create!(
      account: other_target.account,
      token_digest: 'another-session',
      trusted_at: Time.current,
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )

    get settings_account_switch_device_approvals_path

    expect(response.body).to include('table inline-table')
    expect(response.body).to include(target_user.account.pretty_acct)
    expect(response.body).to_not include(other_target.account.pretty_acct)
    expect(response.body).to include('192.0.2.0/24')
  end
end
