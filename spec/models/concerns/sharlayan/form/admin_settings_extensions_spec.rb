# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Form::AdminSettings do
  it 'registers Sharlayan settings with the required storage types' do
    expect(described_class::KEYS).to include(:theme_color, :local_status_page_access, :reactions_enabled, :drive_allowed_extensions)
    expect(described_class::INTEGER_KEYS).to include(:avatar_decorations_max_count, :drive_quota, :drive_max_file_size)
    expect(described_class::BOOLEAN_KEYS).to include(:reactions_enabled, :pages_enabled, :drive_enabled)
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
