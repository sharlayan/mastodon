# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::RoleplayForcedSettings do
  describe '.apply_defaults!' do
    it 'disables optional community features when their settings have not been stored' do
      described_class.apply_defaults!

      expect(Setting.where(var: described_class::DEFAULT_SETTINGS.keys.map(&:to_s)).to_h { |setting| [setting.var, setting.value] }).to eq(
        'avatar_decorations_enabled' => false,
        'circles_enabled' => false,
        'online_status_enabled' => false,
        'rate_limit_bypass_enabled' => true,
        'reactions_enabled' => false,
        'roleplay_disable_local_timeline' => true,
        'status_character_limit' => 1500,
        'user_themes_enabled' => false
      )
    end

    it 'preserves explicitly stored optional feature settings' do
      described_class::DEFAULT_SETTINGS.each { |key, value| Setting.public_send(:"#{key}=", value == 1500 ? 750 : !value) }

      expect { described_class.apply_defaults! }
        .to(not_change { described_class::DEFAULT_SETTINGS.keys.index_with { |key| Setting.public_send(key) } })
    end
  end
end
