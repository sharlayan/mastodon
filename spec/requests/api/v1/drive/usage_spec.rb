# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Drive usage API' do
  include_context 'with API authentication', oauth_scopes: 'read'

  before do
    Setting.drive_enabled = true
    Setting.drive_quota = 500
  end

  it 'returns the quota configured for the user role' do
    user.role.update!(drive_quota: 100)

    get '/api/v1/drive/usage', headers: headers

    expect(response).to have_http_status(200)
    expect(response.parsed_body[:limit]).to eq(100.megabytes)
  end

  it 'returns the server default when the role quota is blank' do
    user.role.update!(drive_quota: nil)

    get '/api/v1/drive/usage', headers: headers

    expect(response).to have_http_status(200)
    expect(response.parsed_body[:limit]).to eq(500.megabytes)
  end
end
