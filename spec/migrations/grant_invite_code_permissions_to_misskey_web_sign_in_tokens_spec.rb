# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db', 'migrate', '20261112191004_grant_invite_code_permissions_to_misskey_web_sign_in_tokens.rb')

RSpec.describe GrantInviteCodePermissionsToMisskeyWebSignInTokens do
  let(:user) { Fabricate(:user) }
  let(:previous_permissions) { MisskeyCompat::MiAuth::SUPPORTED_PERMISSIONS - %w(read:invite-codes write:invite-codes) }

  it 'gives web sign-in grants issued before invite codes the invite code permissions once, leaving MiAuth applications unchanged' do
    web = MisskeyCompat::MiAuth.issue_native_token(user).misskey_access_grant
    web.update_columns(permissions: previous_permissions)
    current = MisskeyCompat::MiAuth.issue_native_token(user).misskey_access_grant
    grant = MisskeyCompat::MiAuth.issue_token(user, name: 'App', permissions: previous_permissions).misskey_access_grant

    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(:up) }

    expect(web.reload.permissions).to match_array(MisskeyCompat::MiAuth::SUPPORTED_PERMISSIONS)
    expect(web.permissions.size).to eq(MisskeyCompat::MiAuth::SUPPORTED_PERMISSIONS.size)
    expect(current.reload.permissions).to eq(MisskeyCompat::MiAuth::SUPPORTED_PERMISSIONS)
    expect(grant.reload.permissions).to eq(previous_permissions)
  end
end
