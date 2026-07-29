# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LowResourceFeatures do
  describe 'defaults' do
    it 'keeps all processing enabled' do
      expect(described_class.trends_processing_enabled?).to be true
      expect(described_class.follow_recommendations_refresh_enabled?).to be true
      expect(described_class.instance_refresh_enabled?).to be true
    end
  end

  describe '.enabled?' do
    it 'uses the default when the option is absent' do
      ClimateControl.modify TEST_RESOURCE_OPTION: nil do
        expect(described_class.send(:enabled?, 'TEST_RESOURCE_OPTION', default: true)).to be true
        expect(described_class.send(:enabled?, 'TEST_RESOURCE_OPTION', default: false)).to be false
      end
    end

    it 'only disables an option when it is explicitly false' do
      ClimateControl.modify TEST_RESOURCE_OPTION: 'false' do
        expect(described_class.send(:enabled?, 'TEST_RESOURCE_OPTION', default: true)).to be false
      end
    end
  end
end
