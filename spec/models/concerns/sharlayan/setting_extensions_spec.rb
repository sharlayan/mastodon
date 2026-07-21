# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::SettingExtensions do
  describe '.merge_defaults' do
    it 'overrides branded defaults and preserves upstream defaults' do
      defaults = described_class.merge_defaults('site_title' => 'Upstream', 'profile_directory' => true)

      expect(defaults).to include(
        'site_title' => 'Mastodon Custard Edition',
        'profile_directory' => true,
        'theme_color' => '#FFFD78'
      )
    end

    it 'provides feature-off defaults for optional integrations' do
      defaults = described_class.merge_defaults({})

      expect(defaults).to include(
        'drive_enabled' => false,
        'misskey_compat_enabled' => false,
        'pages_enabled' => false
      )
    end
  end
end
