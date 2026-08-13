# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::RoleplayForcedSettings do
  describe '.apply_defaults!' do
    it 'disables user themes when the setting has not been stored' do
      described_class.apply_defaults!

      expect(Setting.find_by(var: 'user_themes_enabled').value).to be(false)
    end

    it 'preserves an explicitly stored user themes setting' do
      Setting.user_themes_enabled = true

      expect { described_class.apply_defaults! }
        .to not_change(Setting, :user_themes_enabled)
    end
  end
end
