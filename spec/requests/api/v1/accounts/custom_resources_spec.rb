# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 account custom resources' do
  include_context 'with API authentication', oauth_scopes: 'read:accounts read:lists'

  let(:target_account) { Fabricate(:user).account }

  before do
    Setting.antenna_enabled = true
    Setting.circles_enabled = true
    Setting.clips_enabled = true
    Setting.pages_enabled = true
    target_account.mark_deleted!
  end

  after do
    Setting.antenna_enabled = false
    Setting.circles_enabled = false
    Setting.clips_enabled = false
    Setting.pages_enabled = false
  end

  it 'hides account-scoped custom resources after the account requests deletion', :aggregate_failures do
    %w(antennas exclude_antennas circles clips pages).each do |resource|
      get "/api/v1/accounts/#{target_account.id}/#{resource}", headers: headers

      expect(response).to have_http_status(404), resource
    end
  end
end
