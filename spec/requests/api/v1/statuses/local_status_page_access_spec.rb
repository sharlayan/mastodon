# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Local status page access across status APIs' do
  let(:user) { Fabricate(:user) }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read') }
  let(:headers) { { 'Authorization' => "Bearer #{token.token}" } }
  let(:remote_account) { Fabricate(:account, domain: 'example.com', username: 'remote') }
  let(:local_status) { Fabricate(:status, visibility: :public, text: 'local secret') }
  let(:remote_status) { Fabricate(:status, account: remote_account, visibility: :public) }

  context 'when access requires authentication' do
    before { Setting.local_status_page_access = 'authenticated' }

    it 'omits local statuses from the anonymous multi-status lookup but keeps them for signed-in users' do
      get '/api/v1/statuses', params: { id: [local_status.id, remote_status.id] }

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to contain_exactly(remote_status.id.to_s)

      get '/api/v1/statuses', params: { id: [local_status.id, remote_status.id] }, headers: headers

      expect(response.parsed_body.pluck(:id)).to contain_exactly(local_status.id.to_s, remote_status.id.to_s)
    end

    it 'denies the anonymous edit history of a local status but allows that of a remote status' do
      get "/api/v1/statuses/#{local_status.id}/history"

      expect(response).to_not have_http_status(200)
      expect(response.body).to_not include('local secret')

      get "/api/v1/statuses/#{remote_status.id}/history"

      expect(response).to have_http_status(200)
    end

    it 'omits local replies from the anonymous context of a remote status but keeps them for signed-in users' do
      local_reply = Fabricate(:status, thread: remote_status, visibility: :public)
      remote_reply = Fabricate(:status, account: Fabricate(:account, domain: 'example.com', username: 'other'), thread: remote_status, visibility: :public)

      get "/api/v1/statuses/#{remote_status.id}/context"

      expect(response).to have_http_status(200)
      ids = response.parsed_body[:descendants].pluck(:id)
      expect(ids).to include(remote_reply.id.to_s)
      expect(ids).to_not include(local_reply.id.to_s)

      get "/api/v1/statuses/#{remote_status.id}/context", headers: headers

      expect(response.parsed_body[:descendants].pluck(:id)).to include(local_reply.id.to_s)
    end
  end

  context 'when access is disabled' do
    before { Setting.local_status_page_access = 'disabled' }

    it 'omits local statuses resolved by URL for a regular user but keeps them for a user with the view feeds permission' do
      get '/api/v2/search', params: { q: ActivityPub::TagManager.instance.url_for(local_status), resolve: true, type: 'statuses' }, headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:statuses]).to be_empty

      user.update!(role: Fabricate(:user_role, permissions: UserRole::FLAGS[:view_feeds]))

      get '/api/v2/search', params: { q: ActivityPub::TagManager.instance.url_for(local_status), resolve: true, type: 'statuses' }, headers: headers

      expect(response.parsed_body[:statuses].pluck(:id)).to contain_exactly(local_status.id.to_s)
    end
  end
end
