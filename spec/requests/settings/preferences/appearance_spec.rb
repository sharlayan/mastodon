# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Settings Preferences Appearance' do
  describe 'GET /settings/preferences/appearance' do
    before { sign_in Fabricate(:user) }

    it 'renders the theme selector with standard label spacing' do
      get settings_preferences_appearance_path

      expect(response).to have_http_status(200)
      expect(response.parsed_body.at_css('.input.select.with_label .label_input > label[for="theme"] + .label_input__wrapper select#theme')).to be_present
    end

    it 'hides the theme selector when roleplay mode forces a skin' do
      Setting.roleplay_forced_skin = 'default'

      ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') do
        get settings_preferences_appearance_path
      end

      expect(response).to have_http_status(200)
      expect(response.parsed_body.at_css('select#theme')).to be_nil
    end

    it 'offers both skins for the legacy glitch flavour' do
      get settings_preferences_appearance_path

      expect(response).to have_http_status(200)
      expect(response.parsed_body.css('select#theme option').pluck('value'))
        .to include('glitch-classic/default', 'glitch-classic/birdsiteui')
    end
  end

  describe 'selecting the legacy glitch flavour' do
    let(:user) { Fabricate(:user) }

    before { sign_in user }

    it 'persists the flavour, skin, and supported color scheme' do
      put settings_preferences_appearance_path(theme: 'glitch-classic/birdsiteui', user: { settings_attributes: { 'web.color_scheme': 'light' } })

      user.reload

      expect(user.setting_flavour).to eq('glitch-classic')
      expect(user.setting_skin).to eq('birdsiteui')
      expect(user.setting_color_scheme).to eq('light')

      get settings_preferences_appearance_path

      expect(response.parsed_body.at_css('select#theme option[selected]')['value']).to eq('glitch-classic/birdsiteui')
      expect(response.parsed_body.at_css('html')['data-user-flavour']).to eq('glitch-classic')
    end
  end

  describe 'PUT /settings/preferences/appearance' do
    let(:user) { Fabricate(:user) }

    before do
      sign_in user
      allow(Themes.instance).to receive(:flavours).and_return(%w(glitch schnozzberry))
      allow(Themes.instance).to receive(:skins_for).with('schnozzberry').and_return(%w(wallpaper))
      allow(Themes.instance).to receive(:supported_color_schemes).with('schnozzberry', 'wallpaper').and_return(%w(dark))
    end

    it 'gracefully handles invalid nested params' do
      put settings_preferences_appearance_path(user: 'invalid')

      expect(response)
        .to have_http_status(400)
    end

    it 'updates the theme and adjusts an unsupported color scheme' do
      put settings_preferences_appearance_path(theme: 'schnozzberry/wallpaper', user: { settings_attributes: { 'web.color_scheme': 'light' } })

      user.reload

      expect(user.setting_flavour).to eq('schnozzberry')
      expect(user.setting_skin).to eq('wallpaper')
      expect(user.setting_color_scheme).to eq('dark')
    end

    it 'ignores an unavailable theme' do
      put settings_preferences_appearance_path(theme: 'unknown/default', user: { settings_attributes: { 'web.contrast': 'high' } })

      user.reload

      expect(user.setting_flavour).to eq('glitch')
      expect(user.setting_skin).to eq('default')
      expect(user.setting_contrast).to eq('high')
    end
  end
end
