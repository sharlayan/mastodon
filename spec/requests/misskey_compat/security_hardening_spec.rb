# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat security hardening' do
  let(:user)    { Fabricate(:user) }
  let(:account) { user.account }
  let(:token)   { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write').token }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  describe 'POST /api/users/followers (collection privacy)' do
    let(:target)   { Fabricate(:account) }
    let(:follower) { Fabricate(:account) }

    before { Fabricate(:follow, account: follower, target_account: target) }

    it 'requires an authenticated user' do
      post '/api/users/followers', params: { userId: target.id.to_s }, as: :json
      expect(response).to have_http_status(401)
    end

    it 'returns an empty list when the target hides collections and the viewer is not the owner' do
      target.update!(hide_collections: true)
      post '/api/users/followers', params: { i: token, userId: target.id.to_s }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to eq([])
    end

    it 'exposes the list to the owner even when hidden' do
      account.update!(hide_collections: true)
      Fabricate(:follow, account: follower, target_account: account)

      post '/api/users/followers', params: { i: token, userId: account.id.to_s }, as: :json
      expect(response).to have_http_status(200)
      expect(response.parsed_body.size).to eq(1)
    end
  end

  describe 'POST /api/notes/search' do
    it 'requires an authenticated user' do
      post '/api/notes/search', params: { query: 'hello' }, as: :json
      expect(response).to have_http_status(401)
    end

    it 'returns empty for too-short queries' do
      post '/api/notes/search', params: { i: token, query: 'a' }, as: :json
      expect(response).to have_http_status(200)
      expect(response.parsed_body).to eq([])
    end

    it 'excludes statuses from accounts the viewer blocks' do
      blocked = Fabricate(:account)
      account.block!(blocked)
      Fabricate(:status, account: blocked, text: 'searchable needle', visibility: :public)
      Fabricate(:status, account: account, text: 'searchable needle', visibility: :public)

      post '/api/notes/search', params: { i: token, query: 'needle' }, as: :json
      expect(response).to have_http_status(200)
      author_ids = response.parsed_body.pluck(:userId)
      expect(author_ids).to_not include(blocked.id.to_s)
    end
  end

  describe 'POST /api/users/show (feature gate)' do
    it 'is unavailable when the compat layer is disabled' do
      Setting.misskey_compat_enabled = false
      post '/api/users/show', params: { userId: account.id.to_s }, as: :json
      expect(response).to have_http_status(404)
      expect(response.parsed_body.deep_symbolize_keys[:error][:code]).to eq('ENDPOINT_DISABLED')
    end
  end

  describe 'POST /api/notes/polls/vote (visibility)' do
    it 'rejects voting on a poll in a status the viewer cannot see' do
      other = Fabricate(:account)
      poll = Fabricate(:poll, account: other, options: %w(a b))
      hidden = Fabricate(:status, account: other, visibility: :direct, poll: poll)

      post '/api/notes/polls/vote', params: { i: token, noteId: hidden.id.to_s, choice: 0 }, as: :json
      expect(response).to have_http_status(404)
    end
  end
end
