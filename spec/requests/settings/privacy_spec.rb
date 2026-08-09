# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Settings Privacy' do
  describe 'GET /settings/privacy' do
    it 'hides the RSS preference in roleplay mode' do
      sign_in Fabricate(:user)

      ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') do
        get settings_privacy_path
      end

      expect(response.body).to_not include('account[settings][enable_rss]')
    end
  end

  describe 'PUT /settings/privacy' do
    before { sign_in Fabricate(:user) }

    it 'gracefully handles invalid nested params' do
      put settings_privacy_path(account: 'invalid')

      expect(response)
        .to have_http_status(400)
    end
  end
end
