# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Accounts Search API' do
  include_context 'with API authentication', oauth_scopes: 'read:accounts'

  describe 'GET /api/v1/accounts/search' do
    it 'returns http success' do
      get '/api/v1/accounts/search', params: { q: 'query' }, headers: headers

      expect(response).to have_http_status(200)
      expect(response.content_type)
        .to start_with('application/json')
    end

    it 'limits results to the current account followers' do
      follower = Fabricate(:account, username: 'circlefollower')
      Fabricate(:account, username: 'circlestranger')
      follower.follow!(user.account)

      get '/api/v1/accounts/search', params: { q: 'circle', followers: true }, headers: headers

      expect(response)
        .to have_http_status(200)
        .and have_attributes(parsed_body: contain_exactly(include(id: follower.id.to_s)))
    end
  end
end
