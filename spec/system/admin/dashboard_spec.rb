# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin Dashboard' do
  describe 'Viewing the dashboard page' do
    let(:user) { Fabricate(:owner_user) }

    before do
      Fabricate :software_update
      Fabricate :tag, requested_review_at: 5.minutes.ago
      sign_in(user)
    end

    it 'returns page' do
      visit admin_dashboard_path

      expect(page)
        .to have_title(I18n.t('admin.dashboard.title'))
        .and have_text('0 pending hashtags')
    end

    context 'when roleplay mode found posts that are not local-only at boot' do
      around do |example|
        previous = Rails.configuration.x.roleplay_non_local_only_statuses
        Rails.configuration.x.roleplay_non_local_only_statuses = true
        ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') { example.run }
        Rails.configuration.x.roleplay_non_local_only_statuses = previous
      end

      it 'shows the warning' do
        visit admin_dashboard_path

        expect(page).to have_text(I18n.t('admin.dashboard.roleplay_non_local_only_statuses.title'))
      end
    end

    context 'when forced local-only posting is left enabled outside roleplay mode' do
      around do |example|
        Setting.force_local_only = true
        ClimateControl.modify(OC_ROLEPLAY_OPTION: 'false') { example.run }
        Setting.force_local_only = false
      end

      it 'shows the notice' do
        visit admin_dashboard_path

        expect(page).to have_text(I18n.t('admin.dashboard.force_local_only_notice.title'))
      end
    end
  end
end
