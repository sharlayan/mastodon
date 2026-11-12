# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat channels' do
  let(:user)       { Fabricate(:user) }
  let(:account)    { user.account }
  let(:token)      { MisskeyCompat::MiAuth.issue_native_token(user).token }
  let(:read_token) { MisskeyCompat::MiAuth.issue_token(user, permission: 'read:channels').token }
  let(:other_user) { Fabricate(:user) }
  let(:other_token) { MisskeyCompat::MiAuth.issue_native_token(other_user).token }

  before { Setting.misskey_compat_enabled = true }

  after do
    Setting.misskey_compat_enabled = false
    Setting.drive_enabled = false
  end

  def mi(id)
    MisskeyCompat::MiId.encode(id)
  end

  def api(endpoint, **params)
    post "/api/#{endpoint}", params: params, as: :json
    response.parsed_body
  end

  describe 'channel management' do
    it 'creates, shows, updates and lists owned channels with Drive banners and pinned notes' do
      Setting.drive_enabled = true
      banner = DriveFile.create!(account: account, file: attachment_fixture('attachment.jpg'))
      pinned = Fabricate(:status, account: account, text: 'pinned')
      hidden = Fabricate(:status, account: Fabricate(:account), visibility: :direct)

      created = api('channels/create', i: token, name: 'Lobby', description: 'Talk', bannerId: mi(banner.id), color: '#ff0000', isSensitive: true)

      expect(response).to have_http_status(200)
      expect(created).to include(
        name: 'Lobby', description: 'Talk', userId: mi(account.id), bannerId: mi(banner.id), color: '#ff0000',
        isArchived: false, isSensitive: true, allowRenoteToExternal: true, notesCount: 0, usersCount: 0, lastNotedAt: nil,
        pinnedNoteIds: [], isFollowing: false, isFavorited: false, isMuting: false, hasUnreadNote: false
      )
      expect(created[:bannerUrl]).to be_present
      expect(created).to_not have_key(:pinnedNotes)

      updated = api('channels/update', i: token, channelId: created[:id], name: 'Hall', description: nil, bannerId: nil, pinnedNoteIds: [mi(pinned.id), mi(hidden.id)], allowRenoteToExternal: false)
      expect(updated).to include(name: 'Hall', description: nil, bannerId: nil, bannerUrl: nil, color: '#ff0000', allowRenoteToExternal: false, pinnedNoteIds: [mi(pinned.id), mi(hidden.id)])

      shown = api('channels/show', channelId: created[:id])
      expect(shown[:pinnedNotes].pluck(:id)).to eq([mi(pinned.id)])
      expect(shown).to_not have_key(:isFollowing)

      expect(api('channels/owned', i: read_token).pluck(:id)).to eq([created[:id]])

      api('channels/update', i: token, channelId: created[:id], isArchived: true)
      expect(api('channels/owned', i: read_token)).to eq([])
      expect(api('channels/show', i: token, channelId: created[:id])).to include(isArchived: true, isFollowing: false)
    end

    it 'enforces ownership and lets moderators edit any channel' do
      channel = MisskeyChannel.create!(account: account, name: 'Mine')

      expect(api('channels/update', i: other_token, channelId: mi(channel.id), name: 'Taken')[:error]).to include(code: 'ACCESS_DENIED', id: '1fb7cb09-d46a-4fdf-b8df-057788cce513')
      expect(response).to have_http_status(403)

      moderator = Fabricate(:moderator_user)
      api('channels/update', i: MisskeyCompat::MiAuth.issue_native_token(moderator).token, channelId: mi(channel.id), isArchived: true)
      expect(response).to have_http_status(200)
      expect(channel.reload.archived).to be(true)

      expect(api('channels/show', channelId: mi(channel.id + 1))[:error]).to include(code: 'NO_SUCH_CHANNEL', id: '6f6c314b-7486-4897-8966-c04a66a02923')
      expect(response).to have_http_status(404)
    end

    it 'validates banners, params and scopes' do
      channel = MisskeyChannel.create!(account: account, name: 'Mine')
      foreign_file = DriveFile.create!(account: other_user.account, file: attachment_fixture('avatar.gif'))

      expect(api('channels/create', i: token, name: 'Banner', bannerId: mi(foreign_file.id))[:error]).to include(code: 'NO_SUCH_FILE', id: 'cd1e9f3e-5a12-4ab4-96f6-5d0a2cc32050')
      Setting.drive_enabled = true
      expect(api('channels/create', i: token, name: 'Banner', bannerId: mi(foreign_file.id))[:error]).to include(code: 'NO_SUCH_FILE')

      [{ name: '' }, { name: 'x' * 129 }, { name: 'ok', color: '' }, { name: 'ok', isSensitive: 'yes' }, {}].each do |invalid|
        api('channels/create', i: token, **invalid)
        expect(response).to have_http_status(400), invalid.inspect
      end

      api('channels/update', i: token, channelId: mi(channel.id), pinnedNoteIds: 'nope')
      expect(response).to have_http_status(400)

      api('channels/create', i: read_token, name: 'Read only')
      expect(response).to have_http_status(403)

      api('channels/owned')
      expect(response).to have_http_status(401)
      expect(MisskeyChannel.where(account: account).count).to eq(1)
    end
  end

  describe 'discovery' do
    it 'lists featured channels by last note and searches unarchived channels' do
      older = MisskeyChannel.create!(account: account, name: 'Cooking club', description: 'Recipes', last_noted_at: 2.days.ago)
      newer = MisskeyChannel.create!(account: account, name: 'Music', description: 'cooking playlists', last_noted_at: 1.hour.ago)
      MisskeyChannel.create!(account: account, name: 'Quiet cooking')
      MisskeyChannel.create!(account: account, name: 'Old cooking', archived: true, last_noted_at: Time.now.utc)

      expect(api('channels/featured').pluck(:id)).to eq([mi(newer.id), mi(older.id)])

      matches = api('channels/search', query: 'cooking', limit: 10).pluck(:name)
      expect(matches).to contain_exactly('Cooking club', 'Music', 'Quiet cooking')
      expect(api('channels/search', query: 'cooking', type: 'nameOnly', limit: 10).pluck(:name)).to contain_exactly('Cooking club', 'Quiet cooking')
      expect(api('channels/search', query: '', limit: 1, sinceId: mi(older.id)).pluck(:id)).to eq([mi(newer.id)])

      api('channels/search', query: 'x', type: 'other')
      expect(response).to have_http_status(400)
      api('channels/search')
      expect(response).to have_http_status(400)
    end
  end
end
