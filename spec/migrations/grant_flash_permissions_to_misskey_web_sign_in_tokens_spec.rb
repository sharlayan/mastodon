# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db', 'migrate', '20261112191034_grant_flash_permissions_to_misskey_web_sign_in_tokens.rb')

RSpec.describe GrantFlashPermissionsToMisskeyWebSignInTokens do
  let(:user) { Fabricate(:user) }
  let(:previous_permissions) { MisskeyCompat::MiAuth::SUPPORTED_PERMISSIONS - described_class::PERMISSIONS }

  it 'gives web sign-in grants issued before Flash the Flash permissions once, leaving MiAuth applications unchanged' do
    web = MisskeyCompat::MiAuth.issue_native_token(user).misskey_access_grant
    web.update_columns(permissions: previous_permissions)
    current = MisskeyCompat::MiAuth.issue_native_token(user).misskey_access_grant
    grant = MisskeyCompat::MiAuth.issue_token(user, name: 'App', permissions: previous_permissions).misskey_access_grant

    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(:up) }

    expect(web.reload.permissions).to match_array(MisskeyCompat::MiAuth::SUPPORTED_PERMISSIONS)
    expect(current.reload.permissions).to eq(MisskeyCompat::MiAuth::SUPPORTED_PERMISSIONS)
    expect(grant.reload.permissions).to eq(previous_permissions)
  end
end
