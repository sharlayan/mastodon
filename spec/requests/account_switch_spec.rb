# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Account switching' do
  let(:parent_user) { Fabricate(:user) }
  let(:parent)      { parent_user.account }
  let(:child_user)  { Fabricate(:user) }
  let(:child)       { child_user.account }
  let(:other_user)  { Fabricate(:user) }

  let!(:authorization) { Fabricate(:account_switch_authorization, account: parent, target_account: child) }

  def switch_to_child
    sign_in parent_user
    switch_to(child)
  end

  def switch_to(account)
    post switch_account_path, params: { switch_to: account.id }
    if flash[:alert] == I18n.t('account_switcher.device_approval_required')
      AccountSwitchDevice.find_by!(account:).update!(trusted_at: Time.current)
      post switch_account_path, params: { switch_to: account.id }
    end
  end

  def account_switches_as(user)
    token = Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read:accounts')
    get '/api/v1/account_switches', headers: { 'Authorization' => "Bearer #{token.token}" }
    response.parsed_body
  end

  describe 'switching to an authorized child account' do
    it 'signs in as the child and records the parent' do
      switch_to_child

      expect(response).to redirect_to(root_path)

      body = account_switches_as(child_user)
      expect(body[:parent][:id]).to eq(parent.id.to_s)
      expect(body[:root_account_id]).to eq(parent.id.to_s)
    end

    it 'keeps existing linked accounts switchable when new server-stored links are disabled' do
      Setting.server_stored_account_switching_enabled = false

      switch_to_child

      expect(response).to redirect_to(root_path)
      expect(account_switches_as(child_user)[:parent][:id]).to eq(parent.id.to_s)
    ensure
      Setting.server_stored_account_switching_enabled = true
    end

    it 'refuses a disabled child account' do
      child_user.update!(disabled: true)

      switch_to_child

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t('account_switcher.switch_failed'))
    end
  end

  describe 'link authentication' do
    let(:state) { SecureRandom.hex(32) }

    before do
      MultiAccounts::StateStore.store!(state, SecureRandom.uuid, parent_user.id)
    end

    it 'refuses to authorize a disabled target account' do
      child_user.update!(disabled: true)

      expect do
        post multi_accounts_auth_sign_in_path(state: state), params: { user: { email: child_user.email, password: '123456789' } }
      end.to_not change(AccountSwitchAuthorization, :count)

      expect(response).to have_http_status(200)
      expect(response.body).to include(I18n.t('devise.failure.inactive'))
    end

    it 'does not create a new link when server-stored additions are disabled' do
      Setting.server_stored_account_switching_enabled = false

      expect do
        post multi_accounts_auth_sign_in_path(state: state), params: { user: { email: other_user.email, password: '123456789' } }
      end.to_not change(AccountSwitchAuthorization, :count)

      expect(response).to have_http_status(403)
    ensure
      Setting.server_stored_account_switching_enabled = true
    end

    it 'renders and completes an existing link as reauthentication' do
      MultiAccounts::StateStore.update!(state, reauthenticate_account_id: child.id)

      get multi_accounts_auth_sign_in_path(state: state)
      expect(response.body).to include(I18n.t('multi_accounts.auth.reauthenticate_account'))

      expect do
        post multi_accounts_auth_sign_in_path(state: state), params: { user: { email: child_user.email, password: '123456789' } }
      end.to_not change(AccountSwitchAuthorization, :count)

      expect(response.body).to include(I18n.t('multi_accounts.auth.reauthentication_success_message'))
      expect(AccountSwitchDevice.find_by!(account: child)).to be_trusted
    end

    it 'completes existing-link session authentication when new server-stored links are disabled' do
      Setting.server_stored_account_switching_enabled = false
      MultiAccounts::StateStore.update!(state, reauthenticate_account_id: child.id)

      expect do
        post multi_accounts_auth_sign_in_path(state: state), params: { user: { email: child_user.email, password: '123456789' } }
      end.to_not change(AccountSwitchAuthorization, :count)

      expect(response).to have_http_status(200)
      expect(response.body).to include(I18n.t('multi_accounts.auth.reauthentication_success_message'))
      expect(AccountSwitchDevice.find_by!(account: child)).to be_trusted
    ensure
      Setting.server_stored_account_switching_enabled = true
    end

    it 'does not turn reauthentication into a link for another account' do
      MultiAccounts::StateStore.update!(state, reauthenticate_account_id: child.id)

      expect do
        post multi_accounts_auth_sign_in_path(state: state), params: { user: { email: other_user.email, password: '123456789' } }
      end.to_not change(AccountSwitchAuthorization, :count)

      expect(response.body).to include(I18n.t('multi_accounts.auth.reauthentication_account_mismatch'))
      expect(AccountSwitchDevice.find_by(account: other_user.account)).to be_nil
    end
  end

  describe 'while switched into a child account' do
    let(:grandchild_user) { Fabricate(:user) }
    let(:sibling_user) { Fabricate(:user) }

    before do
      Fabricate(:account_switch_authorization, account: child, target_account: grandchild_user.account)
      Fabricate(:account_switch_authorization, account: parent, target_account: sibling_user.account)
      switch_to_child
    end

    it 'does not expose accounts authorized by the child account' do
      body = account_switches_as(child_user)

      expect(body[:children].map { |item| item.dig(:target_account, :id) })
        .to contain_exactly(sibling_user.account.id.to_s)
    end

    it 'does not allow a chained switch through the child authorization' do
      post switch_account_path, params: { switch_to: grandchild_user.account.id }

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t('account_switcher.switch_unauthorized'))
      expect(account_switches_as(child_user)[:parent][:id]).to eq(parent.id.to_s)
    end

    it 'allows switching to another account authorized by the root without increasing depth' do
      switch_to(sibling_user.account)

      expect(response).to redirect_to(root_path)
      body = account_switches_as(sibling_user)
      expect(body[:parent][:id]).to eq(parent.id.to_s)
      expect(body[:root_account_id]).to eq(parent.id.to_s)
    end
  end

  describe 'when linked-account graphs overlap' do
    let(:second_child_user) { Fabricate(:user) }

    before do
      Fabricate(:account_switch_authorization, account: parent, target_account: second_child_user.account)
      Fabricate(:account_switch_authorization, account: child, target_account: second_child_user.account)

      sign_in parent_user
      switch_to(second_child_user.account)
    end

    it 'routes a sibling switch through the inherited root instead of the current account graph' do
      switch_to(child)

      expect(response).to redirect_to(root_path)
      body = account_switches_as(child_user)
      expect(body[:parent][:id]).to eq(parent.id.to_s)
      expect(body[:root_account_id]).to eq(parent.id.to_s)
    end

    it 'rejects the sibling switch when the inherited root no longer authorizes the current account' do
      AccountSwitchAuthorization.find_by!(account: parent, target_account: second_child_user.account).destroy!

      post switch_account_path, params: { switch_to: child.id }

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t('account_switcher.switch_unauthorized'))
      expect(account_switches_as(second_child_user)[:parent]).to be_nil
    end
  end

  describe 'when another account reuses the same browser' do
    it 'does not adopt the parent stack of the previous account' do
      switch_to_child

      body = account_switches_as(other_user)

      expect(body[:parent]).to be_nil
      expect(body[:root_account_id]).to eq(other_user.account.id.to_s)
    end

    it 'discards the persisted stack cookie' do
      switch_to_child
      account_switches_as(other_user)

      expect(cookies[:switch_parent_stack]).to be_blank
    end
  end

  describe 'background polling from the switcher' do
    def poll_as(user, path)
      token = Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read:accounts')
      get path, headers: { 'Authorization' => "Bearer #{token.token}" }
      response.headers['Set-Cookie']
    end

    it 'does not rewrite the session cookie while switched into a child account' do
      switch_to_child

      expect(poll_as(child_user, '/api/v1/account_switches')).to be_blank
      expect(poll_as(child_user, '/api/v1/account_switches/linked_unread_counts')).to be_blank
    end

    it 'does not rewrite the session cookie for a signed-in root account' do
      sign_in parent_user
      get root_path

      expect(poll_as(parent_user, '/api/v1/account_switches')).to_not include('_mastodon_session')
      expect(poll_as(parent_user, '/api/v1/account_switches/linked_unread_counts')).to be_blank
    end
  end

  describe 'when the parent authorization is revoked' do
    it 'releases the parent stack' do
      switch_to_child
      authorization.destroy!

      body = account_switches_as(child_user)

      expect(body[:parent]).to be_nil
      expect(body[:root_account_id]).to eq(child.id.to_s)
    end
  end

  describe 'switching to an unauthorized account' do
    it 'refuses and keeps the current account signed in' do
      sign_in parent_user
      post switch_account_path, params: { switch_to: other_user.account.id }

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t('account_switcher.switch_unauthorized'))
      expect(account_switches_as(parent_user)[:parent]).to be_nil
    end
  end

  describe 'per-account session authorization' do
    let(:sibling_user) { Fabricate(:user) }
    let(:sibling_authorization) { Fabricate(:account_switch_authorization, account: parent, target_account: sibling_user.account) }

    before { sibling_authorization }

    it 'keeps the current account signed in and creates an account-specific request on a new session' do
      sign_in parent_user

      expect do
        post switch_account_path, params: { switch_to: child.id }
      end.to change(AccountSwitchDeviceApproval, :count).by(1)

      approval = AccountSwitchDeviceApproval.last
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t('account_switcher.device_approval_required'))
      expect(approval).to have_attributes(account_id: parent.id, target_account_id: child.id)
      expect(account_switches_as(parent_user)[:parent]).to be_nil
    end

    it 'does not authorize another linked account when one account is approved' do
      sign_in parent_user
      post switch_account_path, params: { switch_to: child.id }
      AccountSwitchDevice.find_by!(account: child).update!(trusted_at: Time.current)
      post switch_account_path, params: { switch_to: child.id }

      post switch_account_path, params: { switch_to: sibling_user.account.id }

      expect(flash[:alert]).to eq(I18n.t('account_switcher.device_approval_required'))
      expect(AccountSwitchDevice.find_by!(account: sibling_user.account)).to_not be_trusted
    end

    it 'retains linked-account authorization when the same device signs in again' do
      sign_in parent_user
      post switch_account_path, params: { switch_to: child.id }
      AccountSwitchDevice.find_by!(account: child).update!(trusted_at: Time.current)

      delete destroy_user_session_path
      sign_in parent_user

      expect do
        post switch_account_path, params: { switch_to: child.id }
      end.to_not change(AccountSwitchDeviceApproval, :count)

      expect(flash[:alert]).to be_nil
      expect(account_switches_as(child_user)[:parent][:id]).to eq(parent.id.to_s)
    end

    it 'still requires approval after the same device authorization was revoked' do
      sign_in parent_user
      post switch_account_path, params: { switch_to: child.id }
      device = AccountSwitchDevice.find_by!(account: child)
      device.update!(trusted_at: Time.current, revoked_at: Time.current)
      AccountSwitchDeviceApproval.delete_all

      delete destroy_user_session_path
      sign_in parent_user

      expect do
        post switch_account_path, params: { switch_to: child.id }
      end.to change(AccountSwitchDeviceApproval, :count).by(1)

      expect(flash[:alert]).to eq(I18n.t('account_switcher.device_approval_required'))
      expect(account_switches_as(parent_user)[:parent]).to be_nil
    end

    it 'fully signs out an active linked session after its device authorization is revoked' do
      switch_to_child
      child.account_switch_devices.find_by!(token_digest: child.account_switch_devices.first.token_digest).update!(revoked_at: Time.current)

      delete destroy_user_session_path

      expect(response).to redirect_to(new_user_session_path)
      expect(cookies[:switch_parent_stack]).to be_blank
    end
  end

  describe 'GET /auth/sign_in with switch_to' do
    it 'does not switch accounts' do
      sign_in parent_user

      get new_user_session_path(switch_to: child.id)

      expect(response).to redirect_to(root_path)
      expect(account_switches_as(parent_user)[:parent]).to be_nil
    end
  end
end
