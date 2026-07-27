# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserRole do
  describe 'extra permissions' do
    it 'inherits permissions from everyone and grants every extra permission to administrators' do
      everyone = described_class.everyone
      everyone.update!(extra_permissions: described_class::EXTRA_FLAGS[:bypass_rate_limit])
      role = Fabricate(:user_role)
      administrator = Fabricate(:user_role, permissions: described_class::FLAGS[:administrator])

      expect(role.can_extra?(:bypass_rate_limit)).to be true

      ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') do
        expect(administrator.computed_extra_permissions).to eq(described_class::ExtraFlags::ALL)
      end
    end

    it 'masks roleplay-only permissions outside roleplay mode' do
      administrator = Fabricate(:user_role, permissions: described_class::FLAGS[:administrator])
      stale = Fabricate(:user_role, extra_permissions: described_class::EXTRA_FLAGS[:view_admin_timeline])

      ClimateControl.modify(OC_ROLEPLAY_OPTION: 'false') do
        expect(administrator.computed_extra_permissions)
          .to eq(described_class::ExtraFlags::ALL & ~described_class::ExtraFlags::ROLEPLAY_ONLY)
        expect(administrator.can_extra?(:view_admin_timeline)).to be false
        expect(administrator.can_extra?(:bypass_rate_limit)).to be true
        expect(stale.can_extra?(:view_admin_timeline)).to be false
      end
    end

    it 'round-trips known keys and ignores unknown keys' do
      role = Fabricate.build(:user_role)

      role.extra_permissions_as_keys = %w(bypass_rate_limit unknown)

      expect(role.extra_permissions_as_keys).to contain_exactly('bypass_rate_limit')
    end

    it 'rejects unknown permission checks' do
      expect { Fabricate.build(:user_role).can_extra?(:unknown) }.to raise_error(ArgumentError)
    end

    it 'prevents non-admin users from changing their own extra permissions' do
      role = Fabricate(:user_role, extra_permissions: 0)
      account = Fabricate(:account, user: Fabricate(:user, role: role))
      role.current_account = account
      role.extra_permissions = described_class::EXTRA_FLAGS[:bypass_rate_limit]

      expect(role).to_not be_valid
      expect(role.errors.of_kind?(:extra_permissions_as_keys, :own_role)).to be true
    end
  end
end
