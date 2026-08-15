# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin Settings Other' do
  before { sign_in Fabricate(:admin_user) }

  describe 'GET /admin/settings/detailed_branding' do
    it 'renders the drive controls' do
      get admin_settings_custom_extensions_path

      expect(response).to have_http_status(200)
      expect(response.parsed_body.at_css('input[name="form_admin_settings[drive_enabled]"]')).to be_present
      expect(response.parsed_body.at_css('input[name="form_admin_settings[pages_drive_only]"]')).to be_present
      expect(response.parsed_body.at_css('input[name="form_admin_settings[drive_quota]"][min="0"]')).to be_present
      expect(response.parsed_body.at_css('input[name="form_admin_settings[drive_max_file_size]"][min="1"]')).to be_present
      expect(response.parsed_body.at_css('input[name="form_admin_settings[drive_allowed_extensions]"]')).to be_present
      expect(response.parsed_body.at_css('input[name="form_admin_settings[status_character_limit]"][min="1"]')).to be_present
      expect(response.parsed_body.at_css('input[name="form_admin_settings[profile_fields_limit]"][min="0"][max="50"]')).to be_present
      expect(response.parsed_body.at_css('input[name="form_admin_settings[remote_media_attachments_limit]"][min="4"][max="16"]')).to be_present
    end

    it 'renders a separate default-off signin-flow control' do
      get admin_settings_custom_misskey_flavour_path

      expect(response).to have_http_status(200)
      expect(response.parsed_body.at_css('input[name="form_admin_settings[misskey_compat_signin_flow_enabled]"]')).to be_present
      expect(response.parsed_body.at_css('input[name="form_admin_settings[misskey_compat_signin_flow_allowed_origins]"]')).to be_present
      expect(Setting.misskey_compat_signin_flow_enabled).to be false
    end

    it 'renders the federation request counter as an editable default-on control' do
      get admin_settings_custom_extensions_path

      expect(response).to have_http_status(200)
      expect(response.parsed_body.at_css('input[name="form_admin_settings[federation_request_statistics_enabled]"][disabled]')).to be_nil
      expect(Setting.federation_request_statistics_enabled).to be true
    end

    it 'renders the federation graph aggregation as an editable opt-in control' do
      get admin_settings_custom_extensions_path

      expect(response).to have_http_status(200)
      expect(response.parsed_body.at_css('input[name="form_admin_settings[federation_instance_edges_enabled]"][disabled]')).to be_nil
      expect(Setting.federation_instance_edges_enabled).to be false
    end

    it 'disables both federation statistics controls in roleplay mode' do
      ClimateControl.modify OC_ROLEPLAY_OPTION: 'true' do
        get admin_settings_custom_extensions_path
      end

      expect(response).to have_http_status(200)
      expect(response.parsed_body.at_css('input[name="form_admin_settings[federation_request_statistics_enabled]"][disabled]')).to be_present
      expect(response.parsed_body.at_css('input[name="form_admin_settings[federation_instance_edges_enabled]"][disabled]')).to be_present
    end

    it 'shows soft-hide deletion only in roleplay mode' do
      ClimateControl.modify OC_ROLEPLAY_OPTION: 'false' do
        get admin_settings_custom_extensions_path
      end

      expect(response.parsed_body.at_css('input[type="checkbox"][name="form_admin_settings[soft_hide_deletion]"]')).to be_nil

      ClimateControl.modify OC_ROLEPLAY_OPTION: 'true' do
        get admin_settings_custom_extensions_path
      end

      expect(response.parsed_body.at_css('input[type="checkbox"][name="form_admin_settings[soft_hide_deletion]"]')).to be_present
    end
  end

  describe 'PUT /admin/settings/detailed_branding' do
    it 'keeps the counter off at runtime in roleplay mode even when a crafted request enables it' do
      ClimateControl.modify OC_ROLEPLAY_OPTION: 'true' do
        patch admin_settings_custom_extensions_path, params: { form_admin_settings: { federation_request_statistics_enabled: '1', federation_instance_edges_enabled: '1' } }

        expect(Sharlayan::FederationRequestTracker).to_not be_enabled
        expect(Sharlayan::FederationEdgeAggregator).to_not be_enabled
      end
    end
  end
end
