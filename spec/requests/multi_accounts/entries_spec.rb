# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Multi-account link entry' do
  let(:parent_user) { Fabricate(:user) }
  let(:parent)      { parent_user.account }
  let(:child_user)  { Fabricate(:user) }
  let(:child)       { child_user.account }

  let!(:authorization) { Fabricate(:account_switch_authorization, account: parent, target_account: child) }

  def stored_state
    MultiAccounts::StateStore.fetch(response.parsed_body[:state])
  end

  it 'requires authentication' do
    get multi_accounts_entry_path

    expect(response).to redirect_to(new_user_session_path)
  end

  it 'records an empty parent stack for a root account' do
    sign_in parent_user

    get multi_accounts_entry_path

    expect(response).to have_http_status(200)
    expect(Array(stored_state[:switch_parent_stack])).to be_empty
  end

  it 'records the root account when the link flow starts from a switched-in account' do
    sign_in parent_user
    post switch_account_path, params: { switch_to: child.id }

    get multi_accounts_entry_path

    expect(response).to have_http_status(200)
    expect(Array(stored_state[:switch_parent_stack])).to eq([parent.id])
  end

  it 'drops the parent stack once the authorization is revoked' do
    sign_in parent_user
    post switch_account_path, params: { switch_to: child.id }
    authorization.destroy!

    get multi_accounts_entry_path

    expect(Array(stored_state[:switch_parent_stack])).to be_empty
  end
end
