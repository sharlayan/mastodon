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

  it 'gives grants issued before chat only the chat permission of the kinds they already had, without duplicating or filling empty grants' do
    miauth = grant_with(previous_permissions)
    web = MisskeyCompat::MiAuth.issue_native_token(user).misskey_access_grant
    web.update_columns(permissions: previous_permissions)
    reader = grant_with(%w(read:account read:notifications))
    writer = grant_with(%w(write:notes))
    empty = grant_with(%w(read:account))
    empty.update_columns(permissions: [])
    current = MisskeyCompat::MiAuth.issue_native_token(user).misskey_access_grant

    migrate!

    expect(miauth.reload.permissions).to match_array(MisskeyCompat::MiAuth::SUPPORTED_PERMISSIONS)
    expect(web.reload.permissions).to match_array(MisskeyCompat::MiAuth::SUPPORTED_PERMISSIONS)
    expect(reader.reload.permissions).to eq(%w(read:account read:notifications read:chat))
    expect(writer.reload.permissions).to eq(%w(write:notes write:chat))
    expect(empty.reload.permissions).to eq([])
    expect(current.reload.permissions).to eq(MisskeyCompat::MiAuth::SUPPORTED_PERMISSIONS)
  end
end
