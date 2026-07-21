# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin Settings Other' do
  before { sign_in Fabricate(:admin_user) }

  describe 'GET /admin/settings/other' do
    it 'renders the drive controls' do
      get admin_settings_other_path

      expect(response).to have_http_status(200)
      expect(response.parsed_body.at_css('input[name="form_admin_settings[drive_enabled]"]')).to be_present
      expect(response.parsed_body.at_css('input[name="form_admin_settings[drive_quota]"][min="0"]')).to be_present
      expect(response.parsed_body.at_css('input[name="form_admin_settings[drive_max_file_size]"][min="1"]')).to be_present
      expect(response.parsed_body.at_css('input[name="form_admin_settings[drive_allowed_extensions]"]')).to be_present
    end

    it 'renders a separate default-off signin-flow control' do
      get admin_settings_other_path

      expect(response).to have_http_status(200)
      expect(response.parsed_body.at_css('input[name="form_admin_settings[misskey_compat_signin_flow_enabled]"]')).to be_present
      expect(Setting.misskey_compat_signin_flow_enabled).to be false
    end
  end
end
