# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin Settings Appearance' do
  before { sign_in Fabricate(:admin_user) }

  describe 'GET /admin/settings/appearance and detailed branding' do
    it 'keeps custom settings out of the appearance tab' do
      get admin_settings_appearance_path

      expect(response.parsed_body.at_css('textarea[name="form_admin_settings[custom_css]"]')).to be_present
      expect(response.parsed_body.at_css('input[name="form_admin_settings[mascot]"]')).to be_present
      expect(response.parsed_body.at_css('input[name="form_admin_settings[user_themes_enabled]"]')).to be_nil
    end

    it 'renders the server background upload only in custom appearance' do
      get admin_settings_appearance_path
      expect(response.parsed_body.at_css('input[name="form_admin_settings[background_image]"]')).to be_nil

      get admin_settings_custom_appearance_path
      expect(response.parsed_body.at_css('input[name="form_admin_settings[background_image]"]')).to be_present
      expect(response.parsed_body.at_css('input[name="form_admin_settings[background_color]"]')).to be_present
      expect(response.parsed_body.at_css('input[name="form_admin_settings[background_opacity]"][min="0"][max="100"]')).to be_present
      expect(response.parsed_body.at_css('input[name="form_admin_settings[background_on_settings_pages]"]')).to be_present
      expect(response.parsed_body.at_css('.user-theme-catalog-example code').text).to include('"light"', '"dark"')
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

    it 'renders timeline controls only in roleplay mode' do
      get admin_settings_custom_timeline_control_path
      expect(response).to have_http_status(404)

      ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') do
        get admin_settings_custom_timeline_control_path

        expect(response).to have_http_status(200)
        expect(response.parsed_body.at_css('input[name="form_admin_settings[roleplay_disable_local_timeline]"]')).to be_present
        expect(response.parsed_body.at_css('input[name="form_admin_settings[roleplay_hide_public_timelines_from_admins]"]')).to be_present
      end
    end
  end

  describe 'PUT /admin/settings/detailed_branding' do
    it 'stores the server background image' do
      patch admin_settings_custom_appearance_path, params: {
        form_admin_settings: {
          background_image: fixture_file_upload('600x400.webp', 'image/webp'),
          background_color: '#102030',
          background_opacity: '45',
          background_on_settings_pages: '1',
        },
      }

      expect(response).to redirect_to(admin_settings_custom_appearance_path)
      expect(SiteUpload.find_by(var: 'background_image')).to be_present
      expect(Setting.background_color).to eq('#102030')
      expect(Setting.background_opacity).to eq(45)
      expect(Setting.background_on_settings_pages).to be(true)
    end

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
