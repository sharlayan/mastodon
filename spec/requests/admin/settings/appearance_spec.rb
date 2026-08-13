# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin Settings Appearance' do
  before { sign_in Fabricate(:admin_user) }

  describe 'GET /admin/settings/appearance and detailed branding' do
    it 'keeps custom settings out of the appearance tab' do
      get admin_settings_appearance_path

      expect(response.parsed_body.at_css('input[name="form_admin_settings[user_themes_enabled]"]')).to be_nil
    end

    it 'hides cat settings in roleplay mode' do
      ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') do
        get admin_settings_custom_misskey_flavour_path

        expect(response).to have_http_status(200)
        expect(response.parsed_body.at_css('input[name="form_admin_settings[cat_enabled]"]')).to be_nil
        expect(response.parsed_body.at_css('input[name="form_admin_settings[cat_federation_enabled]"]')).to be_nil
      end
    end

    it 'renders the forced roleplay theme selector only in roleplay mode' do
      get admin_settings_appearance_path
      expect(response.parsed_body.at_css('select[name="form_admin_settings[roleplay_forced_skin]"]')).to be_nil

      ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') do
        get admin_settings_custom_appearance_path

        expect(response.parsed_body.at_css('select[name="form_admin_settings[roleplay_forced_skin]"]')).to be_present
      end
    end
  end

  describe 'PUT /admin/settings/detailed_branding' do
    it 'stores server theme JSON as settings' do
      catalog = '[{"id":"ocean","name":"Ocean","variables":{"dark":{"--color-bg-primary":"#001122"}}}]'
      defaults = '{"dark":{"theme":"ocean"}}'

      patch admin_settings_custom_appearance_path, params: { form_admin_settings: { user_themes_enabled: '1', user_theme_catalog: catalog, user_theme_defaults: defaults } }

      expect(response).to redirect_to(admin_settings_custom_appearance_path)
      expect(Setting.user_themes_enabled).to be(true)
      expect(Setting.user_theme_catalog).to eq(catalog)
      expect(Setting.user_theme_defaults).to eq(defaults)
    end

    it 'stores an installed forced roleplay theme' do
      allow(Themes.instance).to receive(:skins_for).with('glitch').and_return(%w(default contrast))

      ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') do
        patch admin_settings_custom_appearance_path, params: { form_admin_settings: { roleplay_forced_skin: 'contrast' } }
      end

      expect(response).to redirect_to(admin_settings_custom_appearance_path)
      expect(Setting.roleplay_forced_skin).to eq('contrast')
    end
  end
end
