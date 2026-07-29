# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat Pages endpoints' do
  let(:user) { Fabricate(:user) }
  let(:account) { user.account }
  let(:read_token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read').token }
  let(:write_token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'write').token }

  before do
    Setting.misskey_compat_enabled = true
    Setting.pages_enabled = true
  end

  after do
    Setting.misskey_compat_enabled = false
    Setting.pages_enabled = false
  end

  describe 'reading pages' do
    let!(:published_page) { Fabricate(:page, account: account, likes_count: 2) }
    let!(:draft_page) { Fabricate(:page, account: account, draft: true, likes_count: 10) }
    let!(:password_page) { Fabricate(:page, account: account, visibility: 'password', access_password: 'correct-password', likes_count: 20) }
    let!(:authenticated_page) { Fabricate(:page, account: account, visibility: 'authenticated') }

    it 'returns featured published pages in Misskey format' do
      post '/api/pages/featured', params: { i: read_token }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to contain_exactly(MisskeyCompat::MiId.encode(published_page.id))
      expect(response.parsed_body.first).to include(
        userId: MisskeyCompat::MiId.encode(account.id),
        variables: [],
        script: '',
        likedCount: 2
      )
    end

    it 'requires authentication for featured pages' do
      post '/api/pages/featured', params: {}, as: :json

      expect(response).to have_http_status(401)
      expect(response.parsed_body.dig(:error, :code)).to eq('CREDENTIAL_REQUIRED')
    end

    it 'includes drafts only in their owner i/pages list' do
      post '/api/i/pages', params: { i: read_token }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to contain_exactly(
        MisskeyCompat::MiId.encode(published_page.id),
        MisskeyCompat::MiId.encode(draft_page.id),
        MisskeyCompat::MiId.encode(password_page.id),
        MisskeyCompat::MiId.encode(authenticated_page.id)
      )
    end

    it 'uses 20 items as the default list size' do
      user.update!(role: Fabricate(:user_role, daily_page_limit: 100))
      21.times { Fabricate(:page, account: account) }

      post '/api/i/pages', params: { i: read_token }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body.size).to eq(20)
    end

    it 'returns only published pages from users/pages' do
      post '/api/users/pages', params: { userId: MisskeyCompat::MiId.encode(account.id) }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to contain_exactly(MisskeyCompat::MiId.encode(published_page.id))
      expect(response.parsed_body.first).to include(content: [], attachedFiles: [])
    end

    it 'hides authenticated pages from anonymous users and shows them to signed-in users' do
      post '/api/users/pages', params: { i: read_token, userId: MisskeyCompat::MiId.encode(account.id) }, as: :json
      expect(response.parsed_body.pluck(:id)).to include(MisskeyCompat::MiId.encode(authenticated_page.id))

      post '/api/pages/show', params: { pageId: MisskeyCompat::MiId.encode(authenticated_page.id) }, as: :json
      expect(response).to have_http_status(404)

      post '/api/pages/show', params: { i: read_token, pageId: MisskeyCompat::MiId.encode(authenticated_page.id) }, as: :json
      expect(response).to have_http_status(200)
    end

    it 'shows a public page by username and name' do
      published_page.update!(content: [{ 'id' => 'body', 'type' => 'text', 'text' => 'Full body' }])
      post '/api/pages/show', params: { username: account.username, name: published_page.name }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:id]).to eq(MisskeyCompat::MiId.encode(published_page.id))
      expect(response.parsed_body.dig(:content, 0, :text)).to eq('Full body')
    end

    it 'hides pages from anonymous crawlers according to the owner setting' do
      user.settings['noindex'] = true
      user.save!

      post '/api/pages/show',
           params: { pageId: MisskeyCompat::MiId.encode(published_page.id) },
           headers: { 'User-Agent' => 'Googlebot/2.1' },
           as: :json

      expect(response).to have_http_status(404)
      expect(response.parsed_body.dig(:error, :code)).to eq('NO_SUCH_PAGE')
    end

    it 'shares the anonymous page budget with the REST page routes' do
      identity = Api::AnonymousPageViewLimit::RateLimitIdentity.new("192.0.2.20:#{published_page.id}")
      59.times { RateLimiter.new(identity, family: :anonymous_page_views).record! }

      post '/api/pages/show',
           params: { pageId: MisskeyCompat::MiId.encode(published_page.id) },
           headers: { 'REMOTE_ADDR' => '192.0.2.20' },
           as: :json
      expect(response).to have_http_status(200)

      get "/api/v1/pages/#{published_page.id}", headers: { 'REMOTE_ADDR' => '192.0.2.20' }
      expect(response).to have_http_status(429)
      expect(response.headers['Retry-After'].to_i).to be_positive
      expect(response.parsed_body[:error]).to be_present
    end

    it 'hides a draft from anonymous pages/show' do
      post '/api/pages/show', params: { pageId: MisskeyCompat::MiId.encode(draft_page.id) }, as: :json

      expect(response).to have_http_status(404)
      expect(response.parsed_body.dig(:error, :code)).to eq('NO_SUCH_PAGE')
    end

    it 'hides a password page from public Misskey endpoints' do
      post '/api/pages/show', params: { pageId: MisskeyCompat::MiId.encode(password_page.id) }, as: :json

      expect(response).to have_http_status(404)
      expect(response.parsed_body.dig(:error, :code)).to eq('NO_SUCH_PAGE')
    end

    it 'does not advertise Pages endpoints while the Pages feature is disabled' do
      Setting.pages_enabled = false

      post '/api/endpoints', params: {}, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to_not include('pages/show', 'i/pages', 'i/page-likes', 'users/pages')
    end

    it 'hides pages owned by a suspended account' do
      viewer = Fabricate(:user)
      viewer_token = Fabricate(:accessible_access_token, resource_owner_id: viewer.id, scopes: 'read').token
      account.suspend!

      post '/api/pages/featured', params: { i: viewer_token }, as: :json
      expect(response.parsed_body).to be_empty

      post '/api/users/pages', params: { userId: MisskeyCompat::MiId.encode(account.id) }, as: :json
      expect(response.parsed_body).to be_empty

      post '/api/pages/show', params: { pageId: MisskeyCompat::MiId.encode(published_page.id) }, as: :json
      expect(response).to have_http_status(404)
    end
  end

  describe 'writing pages' do
    let(:media) { Fabricate(:media_attachment, account: account) }
    let(:status) { Fabricate(:status, account: account) }

    it 'creates a page and translates nested Misskey IDs in both directions' do
      content = [{
        id: 'section',
        type: 'section',
        title: 'Section',
        children: [
          { id: 'image', type: 'image', fileId: MisskeyCompat::MiId.encode(media.id), noUpscale: true },
          { id: 'note', type: 'note', note: MisskeyCompat::MiId.encode(status.id), detailed: true },
        ],
      }]

      post '/api/pages/create', params: {
        i: write_token,
        title: 'Compat page',
        name: 'compat-page',
        content: content,
        variables: [],
        script: '',
        eyeCatchingImageId: MisskeyCompat::MiId.encode(media.id),
      }, as: :json

      expect(response).to have_http_status(200)
      page = Page.find(MisskeyCompat::MiId.decode(response.parsed_body[:id]))
      expect(page.content[0]['children']).to include(
        include('fileId' => media.id.to_s, 'noUpscale' => true),
        include('note' => status.id.to_s)
      )
      expect(response.parsed_body.dig(:content, 0, :children)).to include(
        include(fileId: MisskeyCompat::MiId.encode(media.id), noUpscale: true),
        include(note: MisskeyCompat::MiId.encode(status.id))
      )
      expect(response.parsed_body[:eyeCatchingImageId]).to eq(MisskeyCompat::MiId.encode(media.id))
    end

    it 'preserves supported YouTube block attributes' do
      post '/api/pages/create', params: {
        i: write_token,
        title: 'Video page',
        name: 'video-page',
        content: [{ id: 'video', type: 'youtube', url: 'https://youtu.be/dQw4w9WgXcQ', size: 'small' }],
      }, as: :json

      expect(response).to have_http_status(200)
      page = Page.find(MisskeyCompat::MiId.decode(response.parsed_body[:id]))
      expect(page.content.first).to include('url' => 'https://youtu.be/dQw4w9WgXcQ', 'size' => 'small')
    end

    it 'does not expose or accept Sharlayan spoiler attributes' do
      page = Fabricate(
        :page,
        account: account,
        content: [{ id: 'text', type: 'text', text: 'Hidden', spoiler: true }]
      )

      post '/api/pages/show', params: { pageId: MisskeyCompat::MiId.encode(page.id) }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body.dig(:content, 0)).to_not have_key(:spoiler)
      expect(page.reload.content.first['spoiler']).to be true

      post '/api/pages/create', params: {
        i: write_token,
        title: 'Compat spoiler input',
        name: 'compat-spoiler-input',
        content: [{ id: 'text', type: 'text', text: 'Visible', spoiler: true }],
      }, as: :json

      created = Page.find(MisskeyCompat::MiId.decode(response.parsed_body[:id]))
      expect(created.content.first).to_not have_key('spoiler')
    end

    it 'updates and deletes an owned page with void responses' do
      page = Fabricate(:page, account: account)

      post '/api/pages/update', params: { i: write_token, pageId: MisskeyCompat::MiId.encode(page.id), title: 'Updated' }, as: :json
      expect(response).to have_http_status(204)
      expect(page.reload.title).to eq('Updated')

      post '/api/pages/delete', params: { i: write_token, pageId: MisskeyCompat::MiId.encode(page.id) }, as: :json
      expect(response).to have_http_status(204)
      expect(Page).to_not exist(page.id)
    end

    it 'reuses one pointer when a Drive file is used in the content and header', :attachment_processing do
      Setting.drive_enabled = true
      drive_file = DriveFile.create!(account: account, file: attachment_fixture('attachment.jpg'))
      encoded_file_id = MisskeyCompat::MiId.encode(drive_file.id)

      expect do
        post '/api/pages/create', params: {
          i: write_token,
          title: 'Drive page',
          name: 'drive-page',
          content: [{ id: 'image', type: 'image', fileId: encoded_file_id }],
          variables: [],
          script: '',
          eyeCatchingImageId: encoded_file_id,
        }, as: :json
      end.to change { drive_file.media_attachments.count }.by(1)

      expect(response).to have_http_status(200)
      expect(response.parsed_body.dig(:content, 0, :fileId)).to eq(encoded_file_id)
      expect(response.parsed_body[:eyeCatchingImageId]).to eq(encoded_file_id)
    ensure
      Setting.drive_enabled = false
    end

    it 'rejects updates to another account page' do
      page = Fabricate(:page)

      post '/api/pages/update', params: { i: write_token, pageId: MisskeyCompat::MiId.encode(page.id), title: 'Updated' }, as: :json

      expect(response).to have_http_status(403)
      expect(response.parsed_body.dig(:error, :code)).to eq('ACCESS_DENIED')
    end

    it 'rejects content deeper than the server traversal budget' do
      root = { type: 'section', children: [] }
      current = root
      Page::MAX_BLOCK_DEPTH.times do
        child = { type: 'section', children: [] }
        current[:children] = [child]
        current = child
      end

      post '/api/pages/create', params: { i: write_token, title: 'Deep', name: 'deep', content: [root] }, as: :json

      expect(response).to have_http_status(400)
      expect(response.parsed_body.dig(:error, :code)).to eq('INVALID_PARAM')
    end
  end

  describe 'page likes' do
    let(:other_page) { Fabricate(:page) }

    it 'likes, lists, and unlikes a page' do
      post '/api/pages/like', params: { i: write_token, pageId: MisskeyCompat::MiId.encode(other_page.id) }, as: :json
      expect(response).to have_http_status(204)

      post '/api/i/page-likes', params: { i: read_token }, as: :json
      expect(response).to have_http_status(200)
      expect(response.parsed_body.one?).to be true
      expect(response.parsed_body.first.dig(:page, :id)).to eq(MisskeyCompat::MiId.encode(other_page.id))

      post '/api/pages/unlike', params: { i: write_token, pageId: MisskeyCompat::MiId.encode(other_page.id) }, as: :json
      expect(response).to have_http_status(204)
      expect(account.page_likes).to be_empty
    end

    it 'rejects liking an owned page' do
      own_page = Fabricate(:page, account: account)

      post '/api/pages/like', params: { i: write_token, pageId: MisskeyCompat::MiId.encode(own_page.id) }, as: :json

      expect(response).to have_http_status(400)
      expect(response.parsed_body.dig(:error, :code)).to eq('YOUR_PAGE')
    end

    it 'does not expose a liked page after it becomes a draft' do
      PageLike.create!(account: account, page: other_page)
      other_page.update!(draft: true)

      post '/api/i/page-likes', params: { i: read_token }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to be_empty
    end
  end
end
