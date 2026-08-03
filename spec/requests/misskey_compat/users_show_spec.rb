# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat users/show endpoint' do
  let(:user)    { Fabricate(:user) }
  let(:account) { user.account }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  describe 'account lookup' do
    it 'finds a local account by MiId-encoded userId' do
      post '/api/users/show', params: { userId: MisskeyCompat::MiId.encode(account.id) }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to include(
        id: MisskeyCompat::MiId.encode(account.id),
        username: account.username,
        host: nil
      )
    end

    it 'finds a local account by username when no host is given' do
      post '/api/users/show', params: { username: account.username }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:id]).to eq(MisskeyCompat::MiId.encode(account.id))
    end

    it 'does not fall back to a remote account when no host is given' do
      remote = Fabricate(:account, username: 'ghost', domain: 'remote.example')

      post '/api/users/show', params: { username: remote.username }, as: :json

      expect(response).to have_http_status(404)
      expect(response.parsed_body[:error]).to include(code: 'NO_SUCH_USER')
    end

    it 'finds a remote account by username and host' do
      remote = Fabricate(:account, username: 'ghost', domain: 'remote.example')

      post '/api/users/show', params: { username: remote.username, host: 'remote.example' }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to include(
        id: MisskeyCompat::MiId.encode(remote.id),
        host: 'remote.example'
      )
    end

    it 'returns NO_SUCH_USER for a blank username' do
      post '/api/users/show', params: { username: '   ' }, as: :json

      expect(response).to have_http_status(404)
      expect(response.parsed_body[:error]).to include(code: 'NO_SUCH_USER')
    end

    it 'hides accounts that requested deletion' do
      account.update!(requested_deletion_at: Time.now.utc)

      post '/api/users/show', params: { userId: MisskeyCompat::MiId.encode(account.id) }, as: :json

      expect(response).to have_http_status(404)
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

    it 'returns nothing when decoration federation is disabled' do
      Setting.avatar_decorations_federation_enabled = false

      expect(show_account).to be_empty
    end

    it 'returns nothing when decorations are disabled entirely' do
      Setting.avatar_decorations_enabled = false

      expect(show_account).to be_empty
    end

    it 'returns nothing for a local account while local-only view is on' do
      Setting.avatar_decorations_local_only_view = true

      expect(show_account).to be_empty
    ensure
      Setting.avatar_decorations_local_only_view = false
    end

    it 'returns nothing when the account is decoration-blocked' do
      account.update!(avatar_decorations_blocked: true)

      expect(show_account).to be_empty
    end

    it 'omits decorations whose host is domain-blocked' do
      decoration.update!(host: 'blocked.example')
      Fabricate(:avatar_decoration_domain_block, domain: 'blocked.example')

      expect(show_account).to be_empty
    end
  end
end
