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

    it 'shows the reaction quiet hours fields only while reactions are enabled' do
      sign_in Fabricate(:user, time_zone: 'Asia/Seoul')

      get settings_privacy_path
      expect(response.body).to include('account[settings][reaction_quiet_hours_start]', 'Asia/Seoul')

      Setting.reactions_enabled = false
      get settings_privacy_path
      expect(response.body).to_not include('account[settings][reaction_quiet_hours]')
    end
  end

  describe 'PUT /settings/privacy' do
    before { sign_in Fabricate(:user) }

    it 'saves the reaction quiet hours' do
      put settings_privacy_path(account: { settings: { reaction_quiet_hours: '1', reaction_quiet_hours_start: '22:30', reaction_quiet_hours_end: '06:00' } })

      expect(response).to redirect_to(settings_privacy_path)
      expect(User.last.settings).to have_attributes(reaction_quiet_hours: true, reaction_quiet_hours_start: '22:30', reaction_quiet_hours_end: '06:00')
    end

    it 'gracefully handles invalid nested params' do
      put settings_privacy_path(account: 'invalid')

      expect(response)
        .to have_http_status(400)
    end
  end
end
