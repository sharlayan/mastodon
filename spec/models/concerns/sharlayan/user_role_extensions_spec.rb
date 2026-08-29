# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserRole do
  describe '#rate_limit_for' do
    it 'uses the default when the role override is blank' do
      role = Fabricate.build(:user_role, api_rate_limit: nil)

      expect(role.rate_limit_for(:api)).to eq(1_500)
    end

    it 'uses the role override when present' do
      role = Fabricate.build(:user_role, api_rate_limit: 2_000)

      expect(role.rate_limit_for(:api)).to eq(2_000)
    end
  end

  describe 'rate limit hierarchy validation' do
    let(:base_position) { described_class.maximum(:position).to_i + 1 }
    let!(:lower_role) { Fabricate(:user_role, position: base_position, api_rate_limit: 1_500) }
    let!(:upper_role) { Fabricate(:user_role, position: base_position + 1, api_rate_limit: 2_000) }

    it 'does not allow an upper role limit below a lower role limit' do
      upper_role.api_rate_limit = 1_000

      expect(upper_role).to_not be_valid
      expect(upper_role.errors.of_kind?(:api_rate_limit, :lower_than_subordinate)).to be true
    end

    it 'does not allow a lower role limit above an upper role limit' do
      lower_role.api_rate_limit = 2_500

      expect(lower_role).to_not be_valid
      expect(lower_role.errors.of_kind?(:api_rate_limit, :higher_than_superior)).to be true
    end

    it 'does not validate limits on a role that bypasses rate limits' do
      upper_role.extra_permissions = described_class::EXTRA_FLAGS[:bypass_rate_limit]
      upper_role.api_rate_limit = 1

      expect(upper_role).to be_valid
    end

    it 'does not use a bypassing lower role as a hierarchy baseline' do
      lower_role.update!(extra_permissions: described_class::EXTRA_FLAGS[:bypass_rate_limit], api_rate_limit: 3_000)
      upper_role.api_rate_limit = 1_500

      expect(upper_role).to be_valid
    end

    it 'does not use a bypassing upper role as a hierarchy baseline' do
      upper_role.update!(extra_permissions: described_class::EXTRA_FLAGS[:bypass_rate_limit], api_rate_limit: 1)
      lower_role.api_rate_limit = 3_000

      expect(lower_role).to be_valid
    end
  end

  describe 'rate limit management authorization' do
    let(:target_role) { Fabricate(:user_role, position: 0) }
    let(:account) { Fabricate(:account, user: Fabricate(:user, role: manager_role)) }

    before { target_role.current_account = account }

    context 'when the current role is not the owner or an administrator' do
      let(:manager_role) { Fabricate(:user_role, position: 10, permissions: described_class::FLAGS[:manage_roles]) }

      it 'rejects a rate limit change' do
        target_role.api_rate_limit = 1_500

        expect(target_role).to_not be_valid
        expect(target_role.errors.of_kind?(:api_rate_limit, :restricted)).to be true
      end

      it 'rejects a bypass permission change' do
        target_role.extra_permissions = described_class::EXTRA_FLAGS[:bypass_rate_limit]

        expect(target_role).to_not be_valid
        expect(target_role.errors.of_kind?(:extra_permissions_as_keys, :restricted)).to be true
      end
    end

    context 'when the current role is the owner' do
      let(:manager_role) { Fabricate(:user_role, position: described_class.maximum(:position).to_i + 1, permissions: described_class::FLAGS[:manage_roles]) }

      it 'allows rate limit and bypass permission changes' do
        target_role.api_rate_limit = 1_500
        target_role.extra_permissions = described_class::EXTRA_FLAGS[:bypass_rate_limit]

        expect(target_role).to be_valid
      end
    end

    context 'when the current role is an administrator' do
      let(:manager_role) { Fabricate(:user_role, position: 10, permissions: described_class::FLAGS[:administrator]) }

      it 'allows rate limit and bypass permission changes' do
        target_role.api_rate_limit = 1_500
        target_role.extra_permissions = described_class::EXTRA_FLAGS[:bypass_rate_limit]

        expect(target_role).to be_valid
      end
    end
  end

  describe 'extra permissions' do
    it 'inherits permissions from everyone and grants every extra permission to administrators' do
      everyone = described_class.everyone
      everyone.update!(extra_permissions: described_class::EXTRA_FLAGS[:bypass_rate_limit])
      role = Fabricate(:user_role)
      administrator = Fabricate(:user_role, permissions: described_class::FLAGS[:administrator])

      expect(role.can_extra?(:bypass_rate_limit)).to be true

      ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true', OC_ADMIN_TIMELINE_OPTION: 'true') do
        expect(administrator.computed_extra_permissions).to eq(described_class::ExtraFlags::ALL)
      end
    end

    it 'masks gated permissions while the management timeline gate is off' do
      administrator = Fabricate(:user_role, permissions: described_class::FLAGS[:administrator])
      stale = Fabricate(:user_role, extra_permissions: described_class::EXTRA_FLAGS[:view_admin_timeline])

      [
        { OC_ROLEPLAY_OPTION: 'false', OC_ADMIN_TIMELINE_OPTION: 'false' },
        { OC_ROLEPLAY_OPTION: 'false', OC_ADMIN_TIMELINE_OPTION: 'true' },
        { OC_ROLEPLAY_OPTION: 'true', OC_ADMIN_TIMELINE_OPTION: 'false' },
      ].each do |env|
        ClimateControl.modify(**env) do
          expect(administrator.computed_extra_permissions)
            .to eq(described_class::ExtraFlags::ALL & ~described_class::ExtraFlags::GATED)
          expect(administrator.can_extra?(:view_admin_timeline)).to be false
          expect(administrator.can_extra?(:view_followers_admin_timeline)).to be false
          expect(administrator.can_extra?(:bypass_rate_limit)).to be true
          expect(stale.can_extra?(:view_admin_timeline)).to be false
        end
      end
    end

    it 'drops gated permission keys on assignment while the gate is off' do
      role = Fabricate.build(:user_role)

      ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true', OC_ADMIN_TIMELINE_OPTION: 'false') do
        role.extra_permissions_as_keys = %w(bypass_rate_limit view_admin_timeline)
      end

      expect(role.extra_permissions_as_keys).to contain_exactly('bypass_rate_limit')
    end

    it 'round-trips known keys and ignores unknown keys' do
      role = Fabricate.build(:user_role)

      role.extra_permissions_as_keys = %w(bypass_rate_limit unknown)

      expect(role.extra_permissions_as_keys).to contain_exactly('bypass_rate_limit')
    end

    it 'treats full management timeline access as including follower-scoped access' do
      ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true', OC_ADMIN_TIMELINE_OPTION: 'true') do
        role = Fabricate(:user_role, extra_permissions: described_class::EXTRA_FLAGS[:view_admin_timeline])

        expect(role.can_extra?(:view_followers_admin_timeline)).to be true
      end
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

  describe 'management timeline stream authorization' do
    around do |example|
      ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true', OC_ADMIN_TIMELINE_OPTION: 'true') { example.run }
    end

    it 'disconnects affected streams when the permission is revoked' do
      role = Fabricate(:user_role, extra_permissions: described_class::EXTRA_FLAGS[:view_admin_timeline])
      user = Fabricate(:user, role: role)
      connection = instance_double(Redis)
      allow(connection).to receive(:publish)
      allow(RedisConnection).to receive(:with).and_yield(connection)

      role.update!(extra_permissions: 0)

      expect(connection).to have_received(:publish).with("timeline:system:#{user.account_id}", { event: :kill }.to_json)
    end

    it 'disconnects existing viewers when the top role changes' do
      owner_role = described_class.find_by!(name: 'Owner')
      owner = Fabricate(:user, role: owner_role)
      connection = instance_double(Redis)
      allow(connection).to receive(:publish)
      allow(RedisConnection).to receive(:with).and_yield(connection)

      Fabricate(:user_role, position: described_class.maximum(:position) + 1)

      expect(connection).to have_received(:publish).with("timeline:system:#{owner.account_id}", { event: :kill }.to_json)
    end

    it 'disconnects inherited viewers when the everyone permission is revoked' do
      everyone = described_class.everyone
      everyone.update!(extra_permissions: described_class::EXTRA_FLAGS[:view_admin_timeline])
      user = Fabricate(:user, role: nil)
      connection = instance_double(Redis)
      allow(connection).to receive(:publish)
      allow(RedisConnection).to receive(:with).and_yield(connection)

      everyone.update!(extra_permissions: 0)

      expect(connection).to have_received(:publish).with("timeline:system:#{user.account_id}", { event: :kill }.to_json)
    end
  end
end
