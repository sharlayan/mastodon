# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin Settings Branding' do
  describe 'When signed in as an admin' do
    before { sign_in Fabricate(:admin_user) }

    describe 'GET /admin/settings/detailed_branding' do
      it 'renders each branding logo upload with its display guidance' do
        get admin_settings_detailed_branding_path

        expect(response).to have_http_status(200)
        expect(response.parsed_body.at_css('.content__heading__tabs .material-palette')).to be_present
        expect(response.parsed_body.at_css('input[name="form_admin_settings[logo_icon]"]')).to be_present
        expect(response.parsed_body.at_css('input[name="form_admin_settings[logo_wordmark_dark]"]')).to be_present
        expect(response.parsed_body.at_css('input[name="form_admin_settings[logo_wordmark_light]"]')).to be_present
        expect(response.parsed_body.css('input[name^="form_admin_settings[glitch_mascot"]').size).to eq(4)
        expect(response.body).to include('237×237')
        expect(response.body).to include('Displayed without cropping')
      end
    end

    describe 'PUT /admin/settings/detailed_branding' do
      it 'stores each branding logo type independently' do
        put admin_settings_detailed_branding_path, params: {
          form_admin_settings: {
            logo_icon: fixture_file_upload('avatar.gif', 'image/gif'),
            logo_wordmark_dark: fixture_file_upload('600x400.png', 'image/png'),
            logo_wordmark_light: fixture_file_upload('600x400.webp', 'image/webp'),
          },
        }

        expect(response).to redirect_to(admin_settings_detailed_branding_path)
        expect(SiteUpload.where(var: %w(logo_icon logo_wordmark_dark logo_wordmark_light)).pluck(:var)).to contain_exactly('logo_icon', 'logo_wordmark_dark', 'logo_wordmark_light')
      end

      it 'stores each glitch mascot slot independently' do
        put admin_settings_detailed_branding_path, params: {
          form_admin_settings: {
            glitch_mascot1: fixture_file_upload('avatar.gif', 'image/gif'),
            glitch_mascot4: fixture_file_upload('600x400.webp', 'image/webp'),
          },
        }

        expect(response).to redirect_to(admin_settings_detailed_branding_path)
        expect(SiteUpload.where(var: %w(glitch_mascot1 glitch_mascot4)).pluck(:var)).to contain_exactly('glitch_mascot1', 'glitch_mascot4')
      end

      it 'cannot create a setting value for a non-admin key' do
        expect { put admin_settings_branding_path, params: { form_admin_settings: { new_setting_key: 'New key value' } } }
          .to_not change(Setting, :new_setting_key).from(nil)

        expect(response)
          .to have_http_status(400)
      end
    end
  end
end
