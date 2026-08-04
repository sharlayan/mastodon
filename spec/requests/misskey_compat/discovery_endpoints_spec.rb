# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat discovery endpoints' do
  let(:user)        { Fabricate(:user) }
  let(:account)     { user.account }
  let(:read_token)  { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read').token }
  let(:write_token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'write').token }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  describe 'announcement endpoints' do
    let!(:announcement) do
      BoardAnnouncement.create!(title: 'Notice', text: 'Details', published: true, published_at: Time.current)
    end

    it 'requires a read-capable token' do
      post '/api/announcements', params: { i: write_token }, as: :json

      expect(response).to have_http_status(403)
      expect(response.parsed_body.dig(:error, :code)).to eq('PERMISSION_DENIED')
    end

    it 'returns published announcements and preloads their read state' do
      BoardAnnouncementRead.create!(account: account, board_announcement: announcement)
      BoardAnnouncement.create!(title: 'Draft', text: 'Hidden', published: false)

      post '/api/announcements', params: { i: read_token }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to contain_exactly(
        include(id: MisskeyCompat::MiId.encode(announcement.id), title: 'Notice', isRead: true)
      )
    end

    it 'hides existing-user announcements from accounts created afterwards' do
      announcement.update!(for_existing_users: true, published_at: 1.day.ago, created_at: 1.day.ago)
      account.update!(created_at: Time.current)

      post '/api/announcements/show', params: { i: read_token, announcementId: MisskeyCompat::MiId.encode(announcement.id) }, as: :json

      expect(response).to have_http_status(404)
      expect(response.parsed_body.dig(:error, :code)).to eq('NO_SUCH_ANNOUNCEMENT')
    end
  end

  describe 'ActivityPub lookup endpoints' do
    let(:uri)      { 'https://remote.example/@alice' }
    let(:resolved) { Fabricate(:account, domain: 'remote.example', uri: uri) }

    it 'requires a read-capable token' do
      post '/api/ap/show', params: { i: write_token, uri: uri }, as: :json

      expect(response).to have_http_status(403)
      expect(response.parsed_body.dig(:error, :code)).to eq('PERMISSION_DENIED')
    end

    it 'rejects a blank URI before attempting resolution' do
      allow(ResolveURLService).to receive(:new)

      post '/api/ap/show', params: { i: read_token, uri: ' ' }, as: :json

      expect(response).to have_http_status(400)
      expect(response.parsed_body.dig(:error, :code)).to eq('INVALID_PARAM')
      expect(ResolveURLService).to_not have_received(:new)
    end

    it 'serializes a resolved account as a Misskey User object' do
      resolver = instance_double(ResolveURLService, call: resolved)
      allow(ResolveURLService).to receive(:new).and_return(resolver)

      post '/api/ap/show', params: { i: read_token, uri: uri }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to include(
        type: 'User',
        object: include(id: MisskeyCompat::MiId.encode(resolved.id), host: 'remote.example')
      )
      expect(resolver).to have_received(:call).with(uri, on_behalf_of: account)
    end

    it 'returns NO_SUCH_OBJECT when resolution has no compatible result' do
      allow(ResolveURLService).to receive(:new).and_return(instance_double(ResolveURLService, call: nil))

      post '/api/ap/show', params: { i: read_token, uri: uri }, as: :json

      expect(response).to have_http_status(404)
      expect(response.parsed_body.dig(:error, :code)).to eq('NO_SUCH_OBJECT')
    end
  end

  describe 'role endpoints' do
    let(:role)        { Fabricate(:user_role, name: 'Explorers', highlighted: true, position: 10) }
    let(:member)      { Fabricate(:user, role: role) }
    let(:member_account) { member.account }

    before { member_account.update!(discoverable: true) }

    it 'lists roles that have discoverable members' do
      Fabricate(:user_role, name: 'Hidden role')

      post '/api/roles/list', params: { i: read_token }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to contain_exactly(
        include(id: MisskeyCompat::MiId.encode(role.id), name: 'Explorers', usersCount: 1, asBadge: true)
      )
    end

    it 'returns NO_SUCH_ROLE for an unknown MiId' do
      post '/api/roles/show', params: { i: read_token, roleId: MisskeyCompat::MiId.encode(-1) }, as: :json

      expect(response).to have_http_status(404)
      expect(response.parsed_body.dig(:error, :code)).to eq('NO_SUCH_ROLE')
    end

    it 'lists only discoverable, active members of the selected role' do
      hidden = Fabricate(:user, role: role)
      hidden.account.update!(discoverable: false)
      suspended = Fabricate(:user, role: role)
      suspended.account.update!(discoverable: true, suspended_at: Time.current)

      post '/api/roles/users', params: { i: read_token, roleId: MisskeyCompat::MiId.encode(role.id) }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to contain_exactly(
        include(id: MisskeyCompat::MiId.encode(member_account.id), user: include(id: MisskeyCompat::MiId.encode(member_account.id)))
      )
    end

    it 'returns only public, non-reblog notes from discoverable role members' do
      visible = Fabricate(:status, account: member_account, visibility: :public)
      Fabricate(:status, account: member_account, visibility: :private)
      Fabricate(:status, account: member_account, reblog: visible)

      post '/api/roles/notes', params: { i: read_token, roleId: MisskeyCompat::MiId.encode(role.id) }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to eq([MisskeyCompat::MiId.encode(visible.id)])
    end
  end
end
