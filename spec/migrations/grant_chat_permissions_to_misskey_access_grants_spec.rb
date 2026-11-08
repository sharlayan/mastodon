# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db', 'migrate', '20261109011300_grant_chat_permissions_to_misskey_access_grants.rb')

RSpec.describe GrantChatPermissionsToMisskeyAccessGrants do
  let(:user) { Fabricate(:user) }
  let(:previous_permissions) { MisskeyCompat::MiAuth::SUPPORTED_PERMISSIONS - %w(read:chat write:chat) }

  def migrate!
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(:up) }
  end

  def grant_with(permissions)
    MisskeyCompat::MiAuth.issue_token(user, name: 'App', permissions: permissions).misskey_access_grant
  end

  it 'gives MiAuth applications issued before chat both chat permissions' do
    grant = grant_with(previous_permissions)

    migrate!

    expect(grant.reload.permissions).to match_array(MisskeyCompat::MiAuth::SUPPORTED_PERMISSIONS)
  end

  it 'gives web sign-in grants issued before chat both chat permissions' do
    grant = MisskeyCompat::MiAuth.issue_native_token(user).misskey_access_grant
    grant.update_columns(permissions: previous_permissions)

    migrate!

    expect(grant.reload.permissions).to match_array(MisskeyCompat::MiAuth::SUPPORTED_PERMISSIONS)
  end

  it 'gives a grant only the chat permission of the kinds it already had' do
    reader = grant_with(%w(read:account read:notifications))
    writer = grant_with(%w(write:notes))

    migrate!

    expect(reader.reload.permissions).to eq(%w(read:account read:notifications read:chat))
    expect(writer.reload.permissions).to eq(%w(write:notes write:chat))
  end

  it 'leaves a grant without permissions empty' do
    grant = grant_with(%w(read:account))
    grant.update_columns(permissions: [])

    migrate!

    expect(grant.reload.permissions).to eq([])
  end

  it 'does not duplicate chat permissions that a grant already has' do
    grant = MisskeyCompat::MiAuth.issue_native_token(user).misskey_access_grant

    migrate!

    expect(grant.reload.permissions).to eq(MisskeyCompat::MiAuth::SUPPORTED_PERMISSIONS)
  end
end
