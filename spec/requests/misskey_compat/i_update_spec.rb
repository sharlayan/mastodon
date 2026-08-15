# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat i endpoints' do
  let(:user)        { Fabricate(:user) }
  let(:account)     { user.account }
  let(:token)       { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write').token }
  let(:read_token)  { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read').token }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  describe 'POST /api/i' do
    it 'returns the authenticated account with compat-only fields' do
      post '/api/i', params: { i: token }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to include(
        id: MisskeyCompat::MiId.encode(account.id),
        username: account.username
      )
      expect(response.parsed_body).to include(:hasUnreadAnnouncement, :policies)
    end

    it 'rejects an unauthenticated request' do
      post '/api/i', params: {}, as: :json

      expect(response).to have_http_status(401)
    end
  end

  describe 'POST /api/i/update' do
    def update(params)
      post '/api/i/update', params: params.merge(i: token), as: :json
    end

    it 'rejects a read-only token' do
      post '/api/i/update', params: { i: read_token, name: 'nope' }, as: :json

      expect(response).to have_http_status(403)
      expect(account.reload.display_name).to_not eq('nope')
    end

    it 'rejects a body that is not an object' do
      post "/api/i/update?i=#{token}", params: '[]', headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(400)
      expect(response.parsed_body[:error]).to include(code: 'INVALID_PARAM')
    end

    it 'applies profile fields sent with Misskey names' do
      update(name: 'New Name', description: 'about me', location: 'Seoul', birthday: '1990-01-01')

      expect(response).to have_http_status(200)
      expect(account.reload).to have_attributes(
        display_name: 'New Name',
        location: 'Seoul',
        birthday: '1990-01-01'
      )
      expect(account.note).to eq('about me')
    end

    it 'leaves untouched fields alone' do
      account.update!(display_name: 'Keep Me')

      update(description: 'only the note changes')

      expect(response).to have_http_status(200)
      expect(account.reload.display_name).to eq('Keep Me')
    end

    it 'maps isBot to the Service actor type and isLocked to locked' do
      update(isBot: true, isLocked: true)

      expect(response).to have_http_status(200)
      expect(account.reload).to have_attributes(actor_type: 'Service', locked: true)
    end

    it 'maps isExplorable to discoverable' do
      update(isExplorable: false)

      expect(response).to have_http_status(200)
      expect(account.reload.discoverable).to be(false)
    end

    it 'hides collections unless follow visibility is public' do
      update(followingVisibility: 'private')
      expect(account.reload.hide_collections).to be(true)

      update(followingVisibility: 'public')
      expect(account.reload.hide_collections).to be(false)
    end

    it 'caps profile fields at the configured limit' do
      Setting.profile_fields_limit = 5
      fields = (1..6).map { |i| { name: "k#{i}", value: "v#{i}" } }

      update(fields: fields)

      expect(response).to have_http_status(200)
      expect(account.reload.fields.size).to eq(5)
    end

    it 'stores privacy toggles as user settings' do
      update(noCrawle: true, alwaysMarkNsfw: true, publicReactions: false, hideOnlineStatus: true)

      expect(response).to have_http_status(200)
      user.reload
      expect(user.settings['noindex']).to be(true)
      expect(user.settings['default_sensitive']).to be(true)
      expect(user.settings['show_reactions']).to be(false)
      expect(user.settings['show_online_status']).to be(false)
      expect(response.parsed_body[:hideOnlineStatus]).to be(true)

      update(hideOnlineStatus: false)

      expect(user.reload.settings['show_online_status']).to be(true)
      expect(response.parsed_body[:hideOnlineStatus]).to be(false)
    end

    it 'stores muted words as encoded JSON' do
      update(mutedWords: [['spoiler'], ['two', 'words']])

      expect(response).to have_http_status(200)
      expect(JSON.parse(user.reload.settings['misskey_muted_words'])).to eq([['spoiler'], %w(two words)])
    end

    it 'rejects muted words that are not an array' do
      update(mutedWords: 'spoiler')

      expect(response).to have_http_status(400)
    end

    it 'rejects a muted words payload over the size budget' do
      update(mutedWords: [['x' * (64 * 1024)]])

      expect(response).to have_http_status(400)
    end

    it 'reconciles muted instances against existing domain mutes' do
      account.mute_domain!('old.example')

      update(mutedInstances: ['New.Example ', 'new.example'])

      expect(response).to have_http_status(200)
      expect(account.reload.domain_mutes.pluck(:domain)).to contain_exactly('new.example')
    end

    it 'rejects more muted instances than the limit allows' do
      update(mutedInstances: Array.new(101) { |i| "host#{i}.example" })

      expect(response).to have_http_status(400)
      expect(account.reload.domain_mutes).to be_empty
    end

    it 'rejects more muted emojis than the limit allows' do
      update(mutedEmojis: Array.new(1001) { |i| "emoji#{i}" })

      expect(response).to have_http_status(400)
    end
  end

  describe 'POST /api/i/read-announcement' do
    it 'marks a published announcement as read' do
      announcement = BoardAnnouncement.create!(title: 'Notice', text: 'body', published: true)

      post '/api/i/read-announcement', params: { i: token, announcementId: MisskeyCompat::MiId.encode(announcement.id) }, as: :json

      expect(response).to have_http_status(204)
      expect(BoardAnnouncementRead.exists?(account: account, board_announcement: announcement)).to be(true)
    end

    it 'returns NO_SUCH_ANNOUNCEMENT for an unknown id' do
      post '/api/i/read-announcement', params: { i: token, announcementId: MisskeyCompat::MiId.encode(0) }, as: :json

      expect(response).to have_http_status(404)
      expect(response.parsed_body[:error]).to include(code: 'NO_SUCH_ANNOUNCEMENT')
    end
  end

  describe 'POST /api/i/pin and /api/i/unpin' do
    let(:status) { Fabricate(:status, account: account) }

    it 'pins and unpins the caller own status' do
      post '/api/i/pin', params: { i: token, noteId: MisskeyCompat::MiId.encode(status.id) }, as: :json

      expect(response).to have_http_status(200)
      expect(StatusPin.exists?(account: account, status: status)).to be(true)

      post '/api/i/unpin', params: { i: token, noteId: MisskeyCompat::MiId.encode(status.id) }, as: :json

      expect(response).to have_http_status(200)
      expect(StatusPin.exists?(account: account, status: status)).to be(false)
    end

    it 'refuses to pin somebody else status' do
      other = Fabricate(:status)

      post '/api/i/pin', params: { i: token, noteId: MisskeyCompat::MiId.encode(other.id) }, as: :json

      expect(response).to have_http_status(404)
      expect(response.parsed_body[:error]).to include(code: 'NO_SUCH_NOTE')
      expect(StatusPin.exists?(account: account, status: other)).to be(false)
    end
  end
end
