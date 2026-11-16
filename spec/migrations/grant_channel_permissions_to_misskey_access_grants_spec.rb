# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db', 'migrate', '20261112191025_grant_channel_permissions_to_misskey_access_grants.rb')

RSpec.describe GrantChannelPermissionsToMisskeyAccessGrants do
  let(:user) { Fabricate(:user) }
  let(:previous_permissions) { MisskeyCompat::MiAuth::SUPPORTED_PERMISSIONS - %w(read:channels write:channels) }

  it 'gives only native web sign-in grants the channel permissions, without duplicating them' do
    web = MisskeyCompat::MiAuth.issue_native_token(user).misskey_access_grant
    web.update_columns(permissions: previous_permissions)
    current = MisskeyCompat::MiAuth.issue_native_token(user).misskey_access_grant
    app = MisskeyCompat::MiAuth.issue_token(user, name: 'App', permissions: previous_permissions).misskey_access_grant

    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(:up) }

    expect(web.reload.permissions).to match_array(MisskeyCompat::MiAuth::SUPPORTED_PERMISSIONS)
    expect(current.reload.permissions).to match_array(MisskeyCompat::MiAuth::SUPPORTED_PERMISSIONS)
    expect(app.reload.permissions).to match_array(previous_permissions)
  end
end
