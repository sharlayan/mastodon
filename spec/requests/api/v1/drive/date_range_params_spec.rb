# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Drive date range parameters' do
  include_context 'with API authentication', oauth_scopes: 'read'

  before { Setting.drive_enabled = true }

  it 'does not fail on a huge epoch since_date' do
    get '/api/v1/drive/files', params: { since_date: '9' * 30 }, headers: headers

    expect(response).to have_http_status(200)
  end

  it 'does not fail on a huge epoch until_date' do
    get '/api/v1/drive/files', params: { until_date: '9' * 20 }, headers: headers

    expect(response).to have_http_status(200)
  end

  it 'does not fail on a far future date string' do
    get '/api/v1/drive/files', params: { since_date: '99999999-01-01' }, headers: headers

    expect(response).to have_http_status(200)
  end
end
