# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db', 'migrate', '20261108233800_grant_chat_permissions_to_misskey_web_sign_in_tokens.rb')

RSpec.describe GrantChatPermissionsToMisskeyWebSignInTokens do
  let(:user) { Fabricate(:user) }
  let(:previous_permissions) { MisskeyCompat::MiAuth::SUPPORTED_PERMISSIONS - %w(read:chat write:chat) }

  def migrate!
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(:up) }
  end

  it 'gives web sign-in grants issued before chat the chat permissions once, leaving MiAuth applications unchanged' do
    web = MisskeyCompat::MiAuth.issue_native_token(user).misskey_access_grant
    web.update_columns(permissions: previous_permissions)
    current = MisskeyCompat::MiAuth.issue_native_token(user).misskey_access_grant
    grant = MisskeyCompat::MiAuth.issue_token(user, name: 'App', permissions: previous_permissions).misskey_access_grant
    narrow = MisskeyCompat::MiAuth.issue_token(user, name: 'Reader', permissions: %w(read:account)).misskey_access_grant

    migrate!

    expect(web.reload.permissions).to match_array(MisskeyCompat::MiAuth::SUPPORTED_PERMISSIONS)
    expect(web.permissions.size).to eq(MisskeyCompat::MiAuth::SUPPORTED_PERMISSIONS.size)
    expect(current.reload.permissions).to eq(MisskeyCompat::MiAuth::SUPPORTED_PERMISSIONS)
    expect(grant.reload.permissions).to eq(previous_permissions)
    expect(narrow.reload.permissions).to eq(%w(read:account))
  end
end
