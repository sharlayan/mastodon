# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin Settings Discovery' do
  before { sign_in Fabricate(:admin_user) }

  describe 'GET /admin/settings/discovery' do
    it 'keeps trends editable outside roleplay mode' do
      ClimateControl.modify OC_ROLEPLAY_OPTION: 'false' do
        get admin_settings_discovery_path
      end

      expect(response).to have_http_status(200)
      expect(response.parsed_body.at_css('input[name="form_admin_settings[trends]"][disabled]')).to be_nil
    end

    it 'disables trends in roleplay mode' do
      ClimateControl.modify OC_ROLEPLAY_OPTION: 'true' do
        get admin_settings_discovery_path
      end

      expect(response).to have_http_status(200)
      expect(response.parsed_body.at_css('input[name="form_admin_settings[trends]"][disabled]')).to be_present
    end
  end

  describe 'PUT /admin/settings/discovery' do
    it 'discards a crafted trends enable value in roleplay mode' do
      ClimateControl.modify OC_ROLEPLAY_OPTION: 'true' do
        Setting.trends = false
        put admin_settings_discovery_path, params: { form_admin_settings: { trends: '1' } }
      end

      expect(Setting.trends).to be(false)
    end
  end
end
