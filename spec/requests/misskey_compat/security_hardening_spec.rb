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

  describe 'OAuth token enforcement' do
    it 'rejects an expired token' do
      expired = Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write', created_at: 2.days.ago, expires_in: 1.hour).token

      post '/api/i', params: { i: expired }, as: :json

      expect(response).to have_http_status(401)
      expect(response.parsed_body.dig('error', 'code')).to eq('AUTHENTICATION_FAILED')
    end

    it 'does not allow a read-only token to mutate data' do
      read_token = Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read').token

      post '/api/notes/create', params: { i: read_token, text: 'scope bypass' }, as: :json

      expect(response).to have_http_status(403)
      expect(response.parsed_body.dig('error', 'code')).to eq('PERMISSION_DENIED')
      expect(account.statuses.where(text: 'scope bypass')).to_not exist
    end

    it 'does not allow a write-only token to read private account data' do
      write_token = Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'write').token

      post '/api/i', params: { i: write_token }, as: :json

      expect(response).to have_http_status(403)
      expect(response.parsed_body.dig('error', 'code')).to eq('PERMISSION_DENIED')
    end

    it 'rejects a token owned by a disabled user' do
      user.update!(disabled: true)

      post '/api/i', params: { i: token }, as: :json

      expect(response).to have_http_status(403)
    end

    it 'rejects a token owned by a suspended account' do
      account.update!(suspended_at: Time.current)

      post '/api/i', params: { i: token }, as: :json

      expect(response).to have_http_status(403)
    end
  end

  describe 'relationship exclusion filters' do
    let(:excluded) { Fabricate(:account) }

    before { account.block!(excluded) }

    it 'excludes blocked accounts from follower collections' do
      target = Fabricate(:account)
      Fabricate(:follow, account: excluded, target_account: target)

      post '/api/users/followers', params: { i: token, userId: target.id.to_s }, as: :json

      expect(response.parsed_body).to be_empty
    end

    it 'excludes blocked accounts from following collections' do
      target = Fabricate(:account)
      Fabricate(:follow, account: target, target_account: excluded)

      post '/api/users/following', params: { i: token, userId: target.id.to_s }, as: :json

      expect(response.parsed_body).to be_empty
    end

    it 'excludes blocked reactors from note reaction details' do
      status = Fabricate(:status, account: account)
      Fabricate(:status_reaction, status: status, account: excluded, name: '👍', custom_emoji: nil)

      post '/api/notes/reactions', params: { i: token, noteId: status.id.to_s }, as: :json

      expect(response.parsed_body).to be_empty
    end

    it 'excludes featured notes authored by blocked accounts' do
      status = Fabricate(:status, account: excluded, visibility: :public)
      status.status_stat.update!(favourites_count: 1)

      post '/api/users/featured-notes', params: { i: token, userId: excluded.id.to_s }, as: :json

      expect(response.parsed_body).to be_empty
    end
  end

  describe 'POST /api/users/show (feature gate)' do
    it 'is unavailable when the compat layer is disabled' do
      Setting.misskey_compat_enabled = false
      post '/api/users/show', params: { userId: account.id.to_s }, as: :json
      expect(response).to have_http_status(404)
      expect(response.parsed_body.deep_symbolize_keys[:error][:code]).to eq('ENDPOINT_DISABLED')
    end

    it 'hides an account that has requested deletion' do
      account.mark_deleted!

      post '/api/users/show', params: { userId: account.id.to_s }, as: :json

      expect(response).to have_http_status(404)
      expect(response.parsed_body.dig(:error, :code)).to eq('NO_SUCH_USER')
    end

    it 'hides the deleted account from account content endpoints' do
      target = Fabricate(:user).account
      target.mark_deleted!

      %w(notes followers following reactions featured-notes).each do |endpoint|
        post "/api/users/#{endpoint}", params: { i: token, userId: target.id.to_s }, as: :json

        expect(response).to have_http_status(404), endpoint
        expect(response.parsed_body.dig(:error, :code)).to eq('NO_SUCH_USER'), endpoint
      end
    end

    it 'rejects account-targeting writes for the deleted account' do
      target = Fabricate(:user).account
      target.mark_deleted!

      {
        'following/create' => {},
        'blocking/create' => {},
        'mute/create' => {},
        'users/update-memo' => { memo: 'memo' },
        'users/report-abuse' => { comment: 'report' },
      }.each do |endpoint, extra_params|
        post "/api/#{endpoint}", params: { i: token, userId: target.id.to_s, **extra_params }, as: :json

        expect(response).to have_http_status(404), endpoint
        expect(response.parsed_body.dig(:error, :code)).to eq('NO_SUCH_USER'), endpoint
      end

      list = account.owned_lists.create!(title: 'List')
      post '/api/users/lists/push', params: { i: token, listId: list.id.to_s, userId: target.id.to_s }, as: :json

      expect(response).to have_http_status(404)
      expect(response.parsed_body.dig(:error, :code)).to eq('NO_SUCH_USER')
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
