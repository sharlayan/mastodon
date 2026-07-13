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

  describe '/api/v1/circles/:circle_id/accounts' do
    let(:circle) { Circle.create!(account: user.account, title: 'Friends') }

    before do
      Setting.circles_enabled = true
    end

    it 'rejects a request containing too many account IDs' do
      stub_const 'Circle::ACCOUNTS_PER_REQUEST_LIMIT', 1

      post "/api/v1/circles/#{circle.id}/accounts", headers: headers, params: { account_ids: [user.account.id, Fabricate(:account).id] }

      expect(response).to have_http_status(422)
      expect(circle.circle_accounts).to be_empty
    end

    it 'rejects additions that would exceed the circle member limit' do
      stub_const 'Circle::ACCOUNTS_PER_CIRCLE_LIMIT', 1
      circle.circle_accounts.create!(account: user.account)

      follower = Fabricate(:account)
      follower.follow!(user.account)
      post "/api/v1/circles/#{circle.id}/accounts", headers: headers, params: { account_ids: [follower.id] }

      expect(response).to have_http_status(422)
      expect(circle.accounts.reload).to contain_exactly(user.account)
    end

    it 'treats duplicate account IDs as an idempotent addition' do
      post "/api/v1/circles/#{circle.id}/accounts", headers: headers, params: { account_ids: [user.account.id, user.account.id] }

      expect(response).to have_http_status(200)
      expect(circle.accounts.reload).to contain_exactly(user.account)
    end

    it 'caps the legacy zero limit instead of returning every member' do
      circle.circle_accounts.create!(account: user.account)
      follower = Fabricate(:account)
      follower.follow!(user.account)
      circle.circle_accounts.create!(account: follower)
      stub_const 'Circle::ACCOUNTS_PER_REQUEST_LIMIT', 1

      get "/api/v1/circles/#{circle.id}/accounts", headers: headers, params: { limit: 0 }

      expect(response).to have_http_status(200)
      expect(response.parsed_body.size).to eq(1)
    end
  end
end
