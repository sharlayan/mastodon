# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat admin announcements' do
  let(:role) { Fabricate(:user_role, permissions: UserRole::FLAGS[:manage_announcements]) }
  let(:user) { Fabricate(:user, role: role) }
  let(:token) { MisskeyCompat::MiAuth.issue_native_token(user).token }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  def api(path, **params)
    post "/api/admin/announcements/#{path}", params: { i: token }.merge(params), as: :json
    response.parsed_body
  end

  def create_with_image
    stub_request(:get, 'https://images.example/banner.png').to_return(status: 200, body: Rails.root.join('spec', 'fixtures', 'files', 'attachment.jpg').read, headers: { 'Content-Type' => 'image/jpeg' })
    api('create', title: 'Hello', text: 'Body', imageUrl: 'https://images.example/banner.png', icon: 'warning', display: 'banner', silence: true)
  end

  it 'creates and lists board announcements with action logs and read counts' do
    created = create_with_image
    announcement = BoardAnnouncement.find(MisskeyCompat::MiId.decode(created[:id]))

    expect(response).to have_http_status(200)
    expect(created).to include(title: 'Hello', text: 'Body', icon: 'warning', display: 'banner', silence: true, forYou: false, imageUrl: be_present)
    expect(announcement).to have_attributes(published: true, account_id: user.account_id)
    expect(Admin::ActionLog.where(target: announcement, action: 'create')).to exist

    BoardAnnouncementRead.create!(account: Fabricate(:account), board_announcement: announcement)
    expect(api('list').sole).to include(id: created[:id], isActive: true, reads: 1, userId: nil, imageUrl: created[:imageUrl])
    expect(api('list', userId: MisskeyCompat::MiId.encode(user.account_id))).to eq([])
  end

  it 'updates, archives and clears images like Misskey' do
    created = create_with_image
    announcement = BoardAnnouncement.find(MisskeyCompat::MiId.decode(created[:id]))

    api('update', id: created[:id], title: 'Changed', isActive: false, imageUrl: created[:imageUrl])
    expect(response).to have_http_status(204)
    expect(announcement.reload).to have_attributes(title: 'Changed', published: false)
    expect(announcement.attachments.count).to eq(1)
    expect(api('list')).to eq([])
    expect(api('list', status: 'archived').pluck(:id)).to eq([created[:id]])

    api('update', id: created[:id], text: 'Again')
    expect(announcement.reload.attachments).to be_empty
    expect(Admin::ActionLog.where(target: announcement, action: 'update').count).to eq(2)
  end

  it 'validates params and rejects unsupported targeting' do
    api('create', title: 'Hello', text: 'Body', imageUrl: nil, display: 'dialog')
    expect(response.parsed_body.dig(:error, :info, :param)).to eq('#/properties/display')

    api('create', title: 'Hello', text: 'Body', imageUrl: nil, userId: MisskeyCompat::MiId.encode(user.account_id))
    expect(response).to have_http_status(400)

    api('create', title: 'Hello', text: 'Body')
    expect(response.parsed_body.dig(:error, :info, :param)).to eq('#/required')

    api('update', id: 'missing0000000000', title: 'x')
    expect(response).to have_http_status(404)
    expect(response.parsed_body.dig(:error, :id)).to eq('d3aae5a7-6372-4cb4-b61c-f511ffc2d7cc')
  end

  it 'archives announcements at the requested millisecond timestamp across admin and reader APIs' do
    freeze_time do
      deadline = 1.hour.from_now
      created = api('create', title: 'Timed', text: 'Body', imageUrl: nil, autoArchiveAt: deadline.to_i * 1000)
      expect(response).to have_http_status(200)
      expect(api('list').sole).to include(autoArchiveAt: deadline.iso8601(3), isActive: true)

      travel 1.hour
      expect(api('list')).to be_empty
      expect(api('list', status: 'archived').sole).to include(id: created[:id], isActive: false)

      BoardAnnouncement.create!(title: 'Private draft', text: 'Unpublished', published: false)

      post '/api/announcements', params: { i: token }, as: :json
      expect(response.parsed_body).to be_empty
      post '/api/announcements', params: { i: token, isActive: false }, as: :json
      expect(response.parsed_body.pluck(:id)).to eq([created[:id]])
      post '/api/i', params: { i: token }, as: :json
      expect(response.parsed_body[:hasUnreadAnnouncement]).to be false

      api('update', id: created[:id], autoArchiveAt: nil)
      expect(response).to have_http_status(204)
      expect(api('list').sole).to include(autoArchiveAt: nil, isActive: true)
    end
  end

  it 'rejects invalid archive times and permits past dates on updates without losing omitted dates' do
    base = { title: 'Timed', text: 'Body', imageUrl: nil }
    [-1, 0, 8_640_000_000_000_001].each do |invalid|
      api('create', **base, autoArchiveAt: invalid)
      expect(response).to have_http_status(400)
      expect(response.parsed_body[:error]).to include(code: 'INVALID_AUTO_ARCHIVE_AT', id: '2a892bd5-487d-46a2-a5fe-3d85ad51defe')
    end
    ['tomorrow', true, []].each do |invalid|
      api('create', **base, autoArchiveAt: invalid)
      expect(response).to have_http_status(400)
      expect(response.parsed_body.dig(:error, :code)).to eq('INVALID_PARAM')
    end

    deadline = 1.day.from_now.change(usec: 123_000)
    created = api('create', **base, autoArchiveAt: (deadline.to_r * 1000).to_i)
    api('update', id: created[:id], title: 'Renamed')
    expect(api('list').sole[:autoArchiveAt]).to eq(deadline.iso8601(3))

    api('update', id: created[:id], autoArchiveAt: -1)
    expect(response.parsed_body[:error]).to include(code: 'INVALID_AUTO_ARCHIVE_AT', id: '01b83d7b-2fd5-4d7c-86c4-d03144d16355')
    api('update', id: created[:id], autoArchiveAt: 0)
    expect(response).to have_http_status(204)
    expect(api('list', status: 'archived').sole[:isActive]).to be false
  end

  it 'maps Misskey moderator requirements to Mastodon role flags and token kinds' do
    announcement = BoardAnnouncement.create!(title: 'Hi', text: 'There', published: true)

    api('delete', id: MisskeyCompat::MiId.encode(announcement.id))
    expect(response).to have_http_status(403)
    expect(response.parsed_body.dig(:error, :code)).to eq('ROLE_PERMISSION_DENIED')

    user.update!(role: Fabricate(:user_role, permissions: UserRole::FLAGS[:administrator]))
    api('delete', id: MisskeyCompat::MiId.encode(announcement.id))
    expect(response).to have_http_status(204)
    expect(Admin::ActionLog.where(target_type: 'BoardAnnouncement', action: 'destroy')).to exist

    plain = Fabricate(:user)
    post '/api/admin/announcements/list', params: { i: MisskeyCompat::MiAuth.issue_native_token(plain).token }, as: :json
    expect(response.parsed_body.dig(:error, :id)).to eq('d33d5333-db36-423d-a8f9-1a2b9549da41')

    post '/api/admin/announcements/list', params: { i: MisskeyCompat::MiAuth.issue_token(user, permission: 'read:account').token }, as: :json
    expect(response.parsed_body.dig(:error, :id)).to eq('1370e5b7-d4eb-4566-bb1d-7748ee6a1838')

    mastodon_token = Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'admin:read')
    post '/api/admin/announcements/list', headers: { 'Authorization' => "Bearer #{mastodon_token.token}" }, as: :json
    expect(response).to have_http_status(200)

    post '/api/admin/announcements/list', as: :json
    expect(response).to have_http_status(401)
  end
end
