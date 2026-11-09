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

    it 'excludes statuses from suspended accounts' do
      suspended = Fabricate(:account)
      hidden = Fabricate(:status, account: suspended, text: 'searchable needle', visibility: :public)
      suspended.suspend!

      post '/api/notes/search', params: { i: token, query: 'needle' }, as: :json

      expect(response.parsed_body.pluck(:id)).to_not include(MisskeyCompat::MiId.encode(hidden.id))
    end
  end

  describe 'POST /api/notes/mentions' do
    it 'excludes mentions from muted and blocked accounts' do
      muted = Fabricate(:account)
      account.mute!(muted)
      shown = Fabricate(:status, account: Fabricate(:account), text: 'hi')
      hidden = Fabricate(:status, account: muted, text: 'hi')
      [shown, hidden].each { |status| Fabricate(:mention, status: status, account: account) }

      post '/api/notes/mentions', params: { i: token }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to eq([MisskeyCompat::MiId.encode(shown.id)])
    end
  end

  describe 'OAuth token enforcement' do
    it 'accepts a bearer token like Misskey, including a case-insensitive scheme with repeated whitespace' do
      post '/api/i', headers: { 'Authorization' => "Bearer #{token}" }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:id]).to eq(MisskeyCompat::MiId.encode(account.id))

      post '/api/i', headers: { 'Authorization' => "bEaReR   #{token}" }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:id]).to eq(MisskeyCompat::MiId.encode(account.id))
    end

    it 'reports invalid bearer tokens and expired tokens as authentication failures' do
      post '/api/i', headers: { 'Authorization' => 'Bearer invalid' }, as: :json

      expect(response).to have_http_status(401)
      expect(response.parsed_body.dig(:error, :code)).to eq('AUTHENTICATION_FAILED')

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

    it 'excludes blocked accounts from follower and following collections' do
      followed = Fabricate(:account)
      following = Fabricate(:account)
      Fabricate(:follow, account: excluded, target_account: followed)
      Fabricate(:follow, account: following, target_account: excluded)

      post '/api/users/followers', params: { i: token, userId: followed.id.to_s }, as: :json

      expect(response.parsed_body).to be_empty

      post '/api/users/following', params: { i: token, userId: following.id.to_s }, as: :json

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

  describe 'optional authentication on public read endpoints' do
    let(:private_note) { Fabricate(:status, account: account, visibility: :direct) }
    let(:public_note) { Fabricate(:status, account: account, visibility: :public) }

    it 'does not allow a write-only token or a MiAuth token without account read permission to read a direct note' do
      {
        'write' => Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'write'),
        'write:notes' => MisskeyCompat::MiAuth.issue_token(user, permissions: ['write:notes']),
      }.each do |label, access_token|
        post '/api/notes/show', params: { i: access_token.token, noteId: private_note.id.to_s }, as: :json

        expect(response).to have_http_status(403), label
        expect(response.parsed_body.dig(:error, :code)).to eq('PERMISSION_DENIED'), label
      end
    end

    it 'does not allow a disabled user to read a direct note using optional authentication' do
      user.update!(disabled: true)

      post '/api/notes/show', params: { i: token, noteId: private_note.id.to_s }, as: :json

      expect(response).to have_http_status(403)
    end

    it 'allows a read token or a MiAuth token with account read permission to read an authorized direct note' do
      access_token = Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read')

      post '/api/notes/show', params: { i: access_token.token, noteId: private_note.id.to_s }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:id]).to eq(MisskeyCompat::MiId.encode(private_note.id))

      miauth_token = MisskeyCompat::MiAuth.issue_token(user, permissions: ['read:account'])
      post '/api/notes/show', params: { i: miauth_token.token, noteId: private_note.id.to_s }, as: :json

      expect(response).to have_http_status(200)
    end

    it 'preserves anonymous public note reads without exposing direct notes anonymously' do
      post '/api/notes/show', params: { noteId: public_note.id.to_s }, as: :json

      expect(response).to have_http_status(200)

      post '/api/notes/show', params: { noteId: private_note.id.to_s }, as: :json

      expect(response).to have_http_status(404)
    end

    it 'does not allow a write-only token to retrieve private account settings or notes through users/show and users/notes' do
      private_note
      access_token = Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'write')

      post '/api/users/show', params: { i: access_token.token, userId: account.id.to_s }, as: :json

      expect(response).to have_http_status(403)

      post '/api/users/notes', params: { i: access_token.token, userId: account.id.to_s }, as: :json

      expect(response).to have_http_status(403)
    end

    it 'rejects invalid credentials instead of silently treating them as anonymous' do
      post '/api/notes/show', params: { i: 'invalid', noteId: public_note.id.to_s }, as: :json

      expect(response).to have_http_status(401)
    end

    it 'keeps public user profiles available without exposing private settings anonymously' do
      post '/api/users/show', params: { userId: account.id.to_s }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to_not have_key(:mutedWords)
    end

    context 'with clips enabled' do
      let(:private_clip) { Fabricate(:clip, account: account, public: false) }
      let(:public_clip) { Fabricate(:clip, account: account, public: true) }

      before { Setting.clips_enabled = true }
      after { Setting.clips_enabled = false }

      it 'requires read access for private clips and keeps public clips available anonymously' do
        access_token = Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'write')

        post '/api/clips/show', params: { i: access_token.token, clipId: private_clip.id.to_s }, as: :json

        expect(response).to have_http_status(403)

        post '/api/clips/show', params: { i: token, clipId: private_clip.id.to_s }, as: :json

        expect(response).to have_http_status(200)

        post '/api/clips/show', params: { clipId: public_clip.id.to_s }, as: :json

        expect(response).to have_http_status(200)
      end
    end

    context 'with pages enabled' do
      let(:private_page) { Fabricate(:page, account: account, visibility: :private) }
      let(:public_page) { Fabricate(:page, account: account, visibility: :public) }

      before { Setting.pages_enabled = true }
      after { Setting.pages_enabled = false }

      it 'requires read access or the page-specific MiAuth permission for private pages' do
        [
          ['write', Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'write'), 403],
          ['read:account', MisskeyCompat::MiAuth.issue_token(user, permissions: ['read:account']), 403],
          ['read:pages', MisskeyCompat::MiAuth.issue_token(user, permissions: ['read:pages']), 200],
        ].each do |label, access_token, status|
          post '/api/pages/show', params: { i: access_token.token, pageId: private_page.id.to_s }, as: :json

          expect(response).to have_http_status(status), label
        end
      end

      it 'keeps public pages available anonymously' do
        post '/api/pages/show', params: { pageId: public_page.id.to_s }, as: :json

        expect(response).to have_http_status(200)
      end
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
