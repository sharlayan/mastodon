# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin Settings Appearance' do
  before { sign_in Fabricate(:admin_user) }

  describe 'GET /admin/settings/appearance' do
    it 'renders user theme server settings' do
      get admin_settings_appearance_path

      expect(response).to have_http_status(200)
      expect(response.parsed_body.at_css('input[name="form_admin_settings[user_themes_enabled]"]')).to be_present
      expect(response.parsed_body.at_css('textarea[name="form_admin_settings[user_theme_catalog]"]')).to be_present
      expect(response.parsed_body.at_css('textarea[name="form_admin_settings[user_theme_defaults]"]')).to be_present
    end
  end

  describe 'PUT /admin/settings/appearance' do
    it 'stores server theme JSON as settings' do
      catalog = '[{"id":"ocean","name":"Ocean","variables":{"dark":{"--color-bg-primary":"#001122"}}}]'
      defaults = '{"dark":{"theme":"ocean"}}'

      put admin_settings_appearance_path, params: { form_admin_settings: { user_themes_enabled: '1', user_theme_catalog: catalog, user_theme_defaults: defaults } }

      expect(response).to redirect_to(admin_settings_appearance_path)
      expect(Setting.user_themes_enabled).to be(true)
      expect(Setting.user_theme_catalog).to eq(catalog)
      expect(Setting.user_theme_defaults).to eq(defaults)
    end
  end
end
