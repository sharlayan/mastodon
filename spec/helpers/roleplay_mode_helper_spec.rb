# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RoleplayModeHelper do
  describe '#roleplay_mode?' do
    it 'follows the environment variable' do
      ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') do
        expect(described_class.roleplay_mode?).to be true
      end

      ClimateControl.modify(OC_ROLEPLAY_OPTION: 'false') do
        expect(described_class.roleplay_mode?).to be false
      end
    end
  end

  describe '#roleplay_non_local_only_statuses?' do
    around do |example|
      previous = Rails.configuration.x.roleplay_non_local_only_statuses
      example.run
      Rails.configuration.x.roleplay_non_local_only_statuses = previous
    end

    it 'is true only when roleplay mode is on and the boot check found posts' do
      Rails.configuration.x.roleplay_non_local_only_statuses = true

      ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') do
        expect(described_class.roleplay_non_local_only_statuses?).to be true
      end

      ClimateControl.modify(OC_ROLEPLAY_OPTION: 'false') do
        expect(described_class.roleplay_non_local_only_statuses?).to be false
      end
    end

    it 'is false when the boot check found no posts' do
      Rails.configuration.x.roleplay_non_local_only_statuses = false

      ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') do
        expect(described_class.roleplay_non_local_only_statuses?).to be false
      end
    end

    it 'is false when the boot check did not run' do
      Rails.configuration.x.roleplay_non_local_only_statuses = nil

      ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') do
        expect(described_class.roleplay_non_local_only_statuses?).to be false
      end
    end
  end

  describe '#force_local_only_leftover?' do
    it 'is true only when the setting is on and roleplay mode is off' do
      Setting.force_local_only = true

      ClimateControl.modify(OC_ROLEPLAY_OPTION: 'false') do
        expect(described_class.force_local_only_leftover?).to be true
      end

      ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') do
        expect(described_class.force_local_only_leftover?).to be false
      end
    end

    it 'is false when the setting is off' do
      Setting.force_local_only = false

      ClimateControl.modify(OC_ROLEPLAY_OPTION: 'false') do
        expect(described_class.force_local_only_leftover?).to be false
      end
    end
  end
end
