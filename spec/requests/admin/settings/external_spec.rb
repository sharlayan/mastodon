# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin Settings External Discovery' do
  describe 'When signed in as an admin' do
    before { sign_in Fabricate(:admin_user) }

    describe 'GET /admin/settings/external' do
      it 'disables forced settings in roleplay mode' do
        ClimateControl.modify OC_ROLEPLAY_OPTION: 'true' do
          get admin_settings_external_path
        end

        expect(response).to have_http_status(200)
        expect(response.parsed_body.at_css('input[name="form_admin_settings[noindex]"][disabled]')).to be_present
        expect(response.parsed_body.at_css('input[name="form_admin_settings[norss]"][disabled]')).to be_present
        expect(response.parsed_body.at_css('input[name="form_admin_settings[authorized_fetch]"][disabled]')).to be_present
      end

      it 'disables authorized fetch when the environment overrides it' do
        ClimateControl.modify OC_ROLEPLAY_OPTION: 'false', AUTHORIZED_FETCH: 'actors' do
          get admin_settings_external_path
        end

        expect(response).to have_http_status(200)
        expect(response.parsed_body.at_css('input[name="form_admin_settings[authorized_fetch]"][disabled]')).to be_present
      end
    end

    describe 'PUT /admin/settings/external' do
      it 'cannot create a setting value for a non-admin key' do
        expect { put admin_settings_external_path, params: { form_admin_settings: { new_setting_key: 'New key value' } } }
          .to_not change(Setting, :new_setting_key).from(nil)

        expect(response)
          .to have_http_status(400)
      end
    end

    describe 'PUT /admin/settings/external with valid params' do
      let(:request) { put admin_settings_external_path, params: { form_admin_settings: { activity_api_enabled: 'false' } } }

      it 'saves the value for a valid key' do
        expect { request }.to change(Setting, :activity_api_enabled).from(true)
        expect(request).to redirect_to(admin_settings_external_path)
        expect(response).to have_http_status(302)
      end

      it 'persists forced settings instead of crafted values in roleplay mode' do
        ClimateControl.modify OC_ROLEPLAY_OPTION: 'true' do
          put admin_settings_external_path, params: { form_admin_settings: { noindex: '0', norss: '0', authorized_fetch: 'none' } }
        end

        expect(Setting.noindex).to be(true)
        expect(Setting.norss).to be(true)
        expect(Setting.authorized_fetch).to be(true)
      end
    end
  end
end
