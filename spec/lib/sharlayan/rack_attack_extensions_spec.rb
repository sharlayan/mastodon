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

    it 'reads the limit from the authenticated user role' do
      expect(request.role_rate_limit(:api)).to eq(2_000)
    end

    it 'uses the default when the role has no override' do
      role.update!(api_rate_limit: nil)

      expect(request.role_rate_limit(:api)).to eq(1_500)
    end

    it 'shares role limits between requests without loading the user again' do
      allow(User).to receive(:includes).and_call_original
      expect(request.role_rate_limit(:api)).to eq(2_000)
      another_request = request_class.new(user.id)

      expect(another_request.role_rate_limit(:api)).to eq(2_000)
      expect(User).to have_received(:includes).once
    end
  end
end
