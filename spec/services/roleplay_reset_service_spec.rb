# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RoleplayResetService do
  subject(:service) { described_class.new }

  let!(:everyone_role) { UserRole.find(UserRole::EVERYONE_ROLE_ID) }
  let!(:role) { Fabricate(:user_role, extra_permissions: UserRole::EXTRA_FLAGS[:view_admin_timeline]) }
  let!(:policy) do
    Fabricate(
      :notification_policy,
      for_not_following: :drop,
      for_not_followers: :drop,
      for_new_accounts: :drop,
      for_private_mentions: :accept
    )
  end

  before do
    Setting.force_local_only = true
    Setting.force_mfm_enabled = true
    everyone_role.update!(permissions: UserRole::Flags::NONE)
  end

  it 'reports changes without applying them by default' do
    expect { service.call }.to_not(change { Setting.find_by(var: 'force_local_only')&.value })

    expect(role.reload.can_extra?(:view_admin_timeline)).to be(true)
    expect(policy.reload.for_private_mentions).to eq('accept')
  end

  it 'restores general-server settings, permissions, and notification defaults' do
    service.call(apply: true)

    expect(Setting.find_by(var: 'force_local_only')).to be_nil
    expect(Setting.find_by(var: 'force_mfm_enabled')).to be_nil
    expect(everyone_role.reload.permissions).to eq(UserRole::Flags::DEFAULT)
    expect(role.reload.can_extra?(:view_admin_timeline)).to be(false)
    expect(policy.reload).to have_attributes(
      for_not_following: 'accept',
      for_not_followers: 'accept',
      for_new_accounts: 'accept',
      for_private_mentions: 'filter'
    )
  end

  it 'refuses to run while roleplay mode is enabled' do
    ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') do
      expect { service.call(apply: true) }.to raise_error(Mastodon::NotPermittedError)
    end
  end
end
