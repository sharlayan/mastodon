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

    it 'uses the default when the option is empty' do
      ClimateControl.modify TEST_RESOURCE_OPTION: '' do
        expect(described_class.send(:enabled?, 'TEST_RESOURCE_OPTION', default: true)).to be true
      end
    end

    it 'disables an option for any false boolean value' do
      %w(false FALSE 0 no off f).each do |value|
        ClimateControl.modify TEST_RESOURCE_OPTION: value do
          expect(described_class.send(:enabled?, 'TEST_RESOURCE_OPTION', default: true)).to be(false), value
        end
      end
    end

    it 'enables an option for a true boolean value' do
      %w(true TRUE 1 yes on).each do |value|
        ClimateControl.modify TEST_RESOURCE_OPTION: value do
          expect(described_class.send(:enabled?, 'TEST_RESOURCE_OPTION', default: false)).to be(true), value
        end
      end
    end
  end
end
