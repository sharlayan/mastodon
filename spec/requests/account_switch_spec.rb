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
    post switch_account_path, params: { switch_to: child.id }
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
      post switch_account_path, params: { switch_to: sibling_user.account.id }

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
      post switch_account_path, params: { switch_to: second_child_user.account.id }
    end

    it 'routes a sibling switch through the inherited root instead of the current account graph' do
      post switch_account_path, params: { switch_to: child.id }

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

      expect(poll_as(parent_user, '/api/v1/account_switches')).to be_blank
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

  describe 'GET /auth/sign_in with switch_to' do
    it 'does not switch accounts' do
      sign_in parent_user

      get new_user_session_path(switch_to: child.id)

      expect(response).to redirect_to(root_path)
      expect(account_switches_as(parent_user)[:parent]).to be_nil
    end
  end
end
