# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat users/show endpoint' do
  let(:user)    { Fabricate(:user) }
  let(:account) { user.account }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  describe 'account lookup' do
    it 'finds a local account by MiId-encoded userId or by username when no host is given' do
      post '/api/users/show', params: { userId: MisskeyCompat::MiId.encode(account.id) }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to include(
        id: MisskeyCompat::MiId.encode(account.id),
        username: account.username,
        host: nil
      )

      post '/api/users/show', params: { username: account.username }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:id]).to eq(MisskeyCompat::MiId.encode(account.id))
    end

    it 'returns existing accounts in userIds order, skipping missing or deleted accounts, and an empty array for empty userIds' do
      remote = Fabricate(:account, username: 'ghost', domain: 'remote.example')
      deleted = Fabricate(:account, requested_deletion_at: Time.now.utc)
      ids = [remote.id, deleted.id, account.id, 0].map { |id| MisskeyCompat::MiId.encode(id) }

      post '/api/users/show', params: { userIds: ids }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to eq([ids.first, ids.third])
      expect(response.parsed_body).to all(include(:avatarDecorations))

      post '/api/users/show', params: { userIds: [] }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to eq([])
    end

    it 'rejects non-string, non-array, and duplicate userIds' do
      id = MisskeyCompat::MiId.encode(account.id)

      [[account.id], id, [id, id]].each do |user_ids|
        post '/api/users/show', params: { userIds: user_ids }, as: :json

        expect(response).to have_http_status(400), user_ids.inspect
        expect(response.parsed_body.dig(:error, :code)).to eq('INVALID_PARAM'), user_ids.inspect
      end
    end

    it 'finds a remote account only by username and host, returning NO_SUCH_USER without a host or for a blank username' do
      remote = Fabricate(:account, username: 'ghost', domain: 'remote.example')

      [{ username: remote.username }, { username: '   ' }].each do |params|
        post '/api/users/show', params: params, as: :json

        expect(response).to have_http_status(404), params.inspect
        expect(response.parsed_body[:error]).to include(code: 'NO_SUCH_USER')
      end

      post '/api/users/show', params: { username: remote.username, host: 'remote.example' }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to include(
        id: MisskeyCompat::MiId.encode(remote.id),
        host: 'remote.example'
      )
    end

    it 'hides accounts that requested deletion' do
      account.update!(requested_deletion_at: Time.now.utc)

      post '/api/users/show', params: { userId: MisskeyCompat::MiId.encode(account.id) }, as: :json

      expect(response).to have_http_status(404)
    end
  end

  describe 'batch lookup' do
    let(:viewer) { Fabricate(:user) }
    let(:token) { Fabricate(:accessible_access_token, resource_owner_id: viewer.id, scopes: 'read').token }

    it 'preserves memos while loading them once for the requested accounts' do
      first = Fabricate(:account)
      second = Fabricate(:account)
      Fabricate(:account_note, account: viewer.account, target_account: first, comment: 'first memo')
      Fabricate(:account_note, account: viewer.account, target_account: second, comment: 'second memo')
      ids = [MisskeyCompat::MiId.encode(second.id), MisskeyCompat::MiId.encode(first.id)]
      queries = []
      callback = ->(_name, _started, _finished, _id, payload) { queries << payload[:sql] unless payload[:cached] }

      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
        post '/api/users/show', params: { i: token, userIds: ids }, as: :json
      end

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to eq(ids)
      expect(response.parsed_body.pluck(:memo)).to eq(['second memo', 'first memo'])
      expect(queries.grep(/FROM "account_notes"/)).to have_attributes(size: 1)
    end
  end

  describe 'avatarDecorations' do
    let(:decoration) { Fabricate(:avatar_decoration) }

    before do
      Setting.avatar_decorations_enabled = true
      Setting.avatar_decorations_federation_enabled = true
      Setting.avatar_decorations_local_only_view = false
      account.update!(avatar_decorations: [{ 'id' => decoration.id, 'angle' => 0.1, 'flip_h' => true, 'offset_x' => 0.0, 'offset_y' => 0.0, 'scale' => 1.2, 'opacity' => 0.9 }])
    end

    after do
      Setting.avatar_decorations_enabled = false
      Setting.avatar_decorations_federation_enabled = false
    end

    def show_account
      post '/api/users/show', params: { userId: MisskeyCompat::MiId.encode(account.id) }, as: :json
      response.parsed_body[:avatarDecorations]
    end

    it 'serializes the stored config in Misskey key style' do
      expect(show_account).to contain_exactly(
        include(
          id: MisskeyCompat::MiId.encode(decoration.id),
          angle: 0.1,
          flipH: true,
          scale: 1.2,
          opacity: 0.9
        )
      )
    end

    it 'returns nothing when decoration federation or decorations are disabled, local-only view is on, the account is blocked, or the host is domain-blocked' do
      Setting.avatar_decorations_federation_enabled = false
      expect(show_account).to be_empty
      Setting.avatar_decorations_federation_enabled = true

      Setting.avatar_decorations_enabled = false
      expect(show_account).to be_empty
      Setting.avatar_decorations_enabled = true

      Setting.avatar_decorations_local_only_view = true
      expect(show_account).to be_empty
      Setting.avatar_decorations_local_only_view = false

      account.update!(avatar_decorations_blocked: true)
      expect(show_account).to be_empty
      account.update!(avatar_decorations_blocked: false)
      expect(show_account).to_not be_empty

      decoration.update!(host: 'blocked.example')
      Fabricate(:avatar_decoration_domain_block, domain: 'blocked.example')
      expect(show_account).to be_empty
    ensure
      Setting.avatar_decorations_local_only_view = false
    end
  end

  describe 'pinned notes and profile of restricted accounts' do
    let!(:public_pin) { Fabricate(:status, account: account, visibility: :public).tap { |status| StatusPin.create!(account: account, status: status) } }

    before { StatusPin.create!(account: account, status: Fabricate(:status, account: account, visibility: :public, local_only: true)) }

    it 'hides local-only pinned notes from anonymous viewers in single and batch lookups' do
      post '/api/users/show', params: { userId: MisskeyCompat::MiId.encode(account.id) }, as: :json

      expect(response.parsed_body[:pinnedNoteIds]).to eq([MisskeyCompat::MiId.encode(public_pin.id)])

      post '/api/users/show', params: { userIds: [MisskeyCompat::MiId.encode(account.id)] }, as: :json

      expect(response.parsed_body.first[:pinnedNoteIds]).to eq([MisskeyCompat::MiId.encode(public_pin.id)])
    end

    it 'does not expose pinned notes or profile text of a suspended account' do
      account.update!(note: 'Secret bio', fields: [{ name: 'Site', value: 'example' }])
      account.suspend!

      post '/api/users/show', params: { userId: MisskeyCompat::MiId.encode(account.id) }, as: :json

      expect(response.parsed_body).to include(pinnedNoteIds: [], description: nil, fields: [])
    end
  end

  describe 'users/featured-notes for anonymous viewers' do
    it 'does not return local-only notes' do
      shared = Fabricate(:status, account: account, visibility: :public)
      local_only = Fabricate(:status, account: account, visibility: :public, local_only: true)
      [shared, local_only].each { |status| status.status_stat.update!(favourites_count: 1) }

      post '/api/users/featured-notes', params: { userId: MisskeyCompat::MiId.encode(account.id) }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to eq([MisskeyCompat::MiId.encode(shared.id)])
    end
  end
end
