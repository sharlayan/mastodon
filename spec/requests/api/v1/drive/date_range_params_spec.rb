# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Drive date range parameters' do
  include_context 'with API authentication', oauth_scopes: 'read'

  before { Setting.drive_enabled = true }

  it 'does not fail on huge epoch or far future date bounds', :aggregate_failures do
    [
      { since_date: '9' * 30 },
      { until_date: '9' * 20 },
      { since_date: '99999999-01-01' },
    ].each do |params|
      get '/api/v1/drive/files', params: params, headers: headers

      expect(response).to have_http_status(200), -> { "#{params.inspect} returned #{response.status}" }
    end
  end
end
