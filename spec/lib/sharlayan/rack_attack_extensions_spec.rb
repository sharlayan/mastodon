# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::RackAttackExtensions do
  describe Sharlayan::RackAttackExtensions::RequestMethods do
    subject(:request) { request_class.new(user.id) }

    let(:request_class) do
      Class.new do
        include Sharlayan::RackAttackExtensions::RequestMethods

        def initialize(user_id)
          @user_id = user_id
        end

        def authenticated_user_id
          @user_id
        end
      end
    end

    let(:role) { Fabricate(:user_role, position: UserRole.maximum(:position).to_i + 1, api_rate_limit: 2_000) }
    let(:user) { Fabricate(:user, role: role) }

    around do |example|
      original_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      example.run
    ensure
      Rails.cache = original_cache
    end

    it 'uses the default when the role has no override' do
      role.update!(api_rate_limit: nil)

      expect(request.role_rate_limit(:api)).to eq(1_500)
    end

    it 'reads the limit from the authenticated user role and shares it between requests without loading the user again' do
      allow(User).to receive(:includes).and_call_original
      expect(request.role_rate_limit(:api)).to eq(2_000)
      another_request = request_class.new(user.id)

      expect(another_request.role_rate_limit(:api)).to eq(2_000)
      expect(User).to have_received(:includes).once
    end

    describe '#bypasses_rate_limit?' do
      before do
        Setting.rate_limit_bypass_enabled = true
        role.update!(extra_permissions: UserRole::EXTRA_FLAGS[:bypass_rate_limit])
      end

      after do
        Setting.rate_limit_bypass_enabled = false
      end

      it 'denies a role without the bypass permission' do
        role.update!(extra_permissions: 0)

        expect(request.bypasses_rate_limit?).to be false
      end

      it 'allows a role with the bypass permission and shares the decision between requests without loading the user again' do
        allow(User).to receive(:includes).and_call_original
        expect(request.bypasses_rate_limit?).to be true
        another_request = request_class.new(user.id)

        expect(another_request.bypasses_rate_limit?).to be true
        expect(User).to have_received(:includes).once
      end

      it 'does not look up anonymous requests or users when the bypass setting is disabled' do
        allow(User).to receive(:includes).and_call_original

        expect(request_class.new(nil).bypasses_rate_limit?).to be false

        Setting.rate_limit_bypass_enabled = false

        expect(request.bypasses_rate_limit?).to be false
        expect(User).to_not have_received(:includes)
      end
    end
  end
end
