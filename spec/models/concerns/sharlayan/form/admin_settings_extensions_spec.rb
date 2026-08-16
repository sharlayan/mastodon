# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Form::AdminSettings do
  it 'registers Sharlayan settings with the required storage types' do
    expect(described_class::KEYS).to include(:theme_color, :background_color, :background_opacity, :local_status_page_access, :norss, :reactions_enabled, :drive_allowed_extensions, :roleplay_forced_skin, :profile_fields_limit, :remote_media_attachments_limit)
    expect(described_class::INTEGER_KEYS).to include(:avatar_decorations_max_count, :background_opacity, :drive_quota, :drive_max_file_size, :status_character_limit, :profile_fields_limit, :remote_media_attachments_limit)
    expect(described_class::BOOLEAN_KEYS).to include(:background_on_settings_pages, :norss, :reactions_enabled, :pages_enabled, :pages_drive_only, :drive_enabled)
  end

  it 'validates optional server background presentation settings' do
    expect(described_class.new(background_color: '', background_opacity: '100')).to be_valid
    expect(described_class.new(background_color: '#12aBcD', background_opacity: '45')).to be_valid
    expect(described_class.new(background_color: 'red', background_opacity: '101')).to_not be_valid
  end

  it 'requires a status character limit of at least 300' do
    expect(described_class.new(status_character_limit: '500')).to be_valid
    expect(described_class.new(status_character_limit: '299')).to_not be_valid
    expect(described_class.new(status_character_limit: '300')).to be_valid
  end

  it 'validates configurable profile and remote media limits' do
    expect(described_class.new(profile_fields_limit: '0', remote_media_attachments_limit: '4')).to be_valid
    expect(described_class.new(profile_fields_limit: '51', remote_media_attachments_limit: '17')).to_not be_valid
  end

  it 'uses MAX_TOOT_CHARS as the default when configured' do
    ClimateControl.modify MAX_TOOT_CHARS: '1000' do
      expect(Sharlayan::SettingExtensions.sharlayan_defaults.fetch('status_character_limit')).to eq(1000)
    end
  end

  it 'uses the configured default when MAX_TOOT_CHARS is invalid or below the minimum' do
    ['invalid', '299', ''].each do |value|
      ClimateControl.modify MAX_TOOT_CHARS: value do
        expect(Sharlayan::SettingExtensions.sharlayan_defaults.fetch('status_character_limit')).to eq(500)
      end
    end
  end

  it 'uses the legacy environment variables as defaults' do
    ClimateControl.modify MAX_PROFILE_FIELDS: '12', REMOTE_MEDIA_ATTACHMENTS_LIMIT: '8' do
      defaults = Sharlayan::SettingExtensions.sharlayan_defaults

      expect(defaults.fetch('profile_fields_limit')).to eq(12)
      expect(defaults.fetch('remote_media_attachments_limit')).to eq(8)
    end
  end

  it 'validates feed access modes and theme colors' do
    settings = described_class.new(local_account_statuses_access: 'unknown', local_status_page_access: 'unknown', theme_color: 'red')

    expect(settings).to_not be_valid
    expect(settings.errors).to include(:local_account_statuses_access, :local_status_page_access, :theme_color)
  end

  it 'accepts valid feed access modes and theme colors' do
    settings = described_class.new(local_account_statuses_access: 'authenticated', local_status_page_access: 'disabled', theme_color: '#12aBcD')

    expect(settings).to be_valid
  end
end
