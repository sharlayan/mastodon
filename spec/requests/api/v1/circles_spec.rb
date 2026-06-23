# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Circles API' do
  include_context 'with API authentication', oauth_scopes: 'read:lists write:lists'

  describe 'GET /api/v1/circles' do
    subject do
      get '/api/v1/circles', headers: headers
    end

    it 'returns not found when circles are disabled' do
      subject

      expect(response).to have_http_status(404)
    end

    it 'returns the current account circles when enabled' do
      Setting.circles_enabled = true
      circle = Circle.create!(account: user.account, title: 'Friends')

      subject

      expect(response)
        .to have_http_status(200)
        .and have_attributes(parsed_body: contain_exactly(include(id: circle.id.to_s, title: 'Friends')))
    end
  end
end
