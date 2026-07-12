# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat users/lists/create-from-public endpoint' do
  let(:user)  { Fabricate(:user) }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write') }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  describe 'POST /api/users/lists/create-from-public' do
    it 'returns an unsupported error envelope' do
      post '/api/users/lists/create-from-public', params: { i: token.token, name: 'x', listId: 'abc' }, as: :json

      expect(response).to have_http_status(501)
      expect(response.parsed_body[:error]).to include(code: 'UNSUPPORTED_ENDPOINT')
    end
  end
end
