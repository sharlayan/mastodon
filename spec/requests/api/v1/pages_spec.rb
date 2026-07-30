# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Pages' do
  include_context 'with API authentication', oauth_scopes: 'read write read:accounts write:accounts'

  before { Setting.pages_enabled = true }

  describe 'POST /api/v1/pages' do
    subject do
      post '/api/v1/pages', params: {
        title: 'Test page',
        name: 'test-page',
        category: ' Guides ',
        draft: true,
        content: [],
        eye_catching_media_attachment_id: media_attachment.id,
      }, headers: headers
    end

    context 'with media owned by the page owner' do
      let(:media_attachment) { Fabricate(:media_attachment, account: user.account) }

      it 'creates the page' do
        expect { subject }.to change(Page, :count).by(1)
        expect(response).to have_http_status(200)
        expect(response.parsed_body[:eye_catching_media_attachment_id]).to eq(media_attachment.id.to_s)
        expect(response.parsed_body[:category]).to eq('Guides')
        expect(response.parsed_body[:draft]).to be true
        page = Page.last
        transaction_timestamp = Page.connection.select_value('SELECT transaction_timestamp()')
        expect(Mastodon::Snowflake.to_time(page.id)).to be_within(1.second).of(transaction_timestamp)
      end
    end

    context 'with media owned by another account' do
      let(:media_attachment) { Fabricate(:media_attachment) }

      it 'rejects the media reference' do
        expect { subject }.to_not change(Page, :count)
        expect(response).to have_http_status(422)
      end
    end
  end

  describe 'draft visibility' do
    let!(:draft_page) { Fabricate(:page, account: user.account, draft: true, likes_count: 10) }
    let!(:published_page) { Fabricate(:page, account: user.account, draft: false, likes_count: 5) }
    let(:other_user) { Fabricate(:user) }
    let(:other_token) { Fabricate(:accessible_access_token, resource_owner_id: other_user.id, scopes: scopes) }
    let(:other_headers) { { 'Authorization' => "Bearer #{other_token.token}" } }

    it 'includes drafts in the owner list' do
      get '/api/v1/pages', headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to contain_exactly(draft_page.id.to_s, published_page.id.to_s)
    end

    it 'allows the owner to open a draft by ID' do
      get "/api/v1/pages/#{draft_page.id}", headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:draft]).to be true
    end

    it 'hides a draft by ID from another user' do
      get "/api/v1/pages/#{draft_page.id}", headers: other_headers

      expect(response).to have_http_status(404)
    end

    it 'hides drafts from the public account list' do
      get "/api/v1/accounts/#{user.account_id}/pages"

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to contain_exactly(published_page.id.to_s)
    end

    it 'hides drafts from featured pages' do
      get '/api/v1/pages/featured', headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to contain_exactly(published_page.id.to_s)
    end

    it 'hides a draft from the account-scoped slug route' do
      get "/api/v1/accounts/#{draft_page.account_id}/pages/#{draft_page.name}"

      expect(response).to have_http_status(404)
    end

    it 'allows the owner to open a draft through the account-scoped slug route' do
      get "/api/v1/accounts/#{draft_page.account_id}/pages/#{draft_page.name}", headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:id]).to eq(draft_page.id.to_s)
    end
  end

  describe 'category validation' do
    let(:media_attachment) { Fabricate(:media_attachment, account: user.account) }

    it 'rejects categories longer than 30 characters' do
      post '/api/v1/pages', params: {
        title: 'Test page',
        name: 'test-page',
        category: 'a' * 31,
        content: [],
        eye_catching_media_attachment_id: media_attachment.id,
      }, headers: headers

      expect(response).to have_http_status(422)
      expect(Page).to_not exist(name: 'test-page')
    end
  end

  describe 'text block formats' do
    it 'stores Markdown format and returns server-rendered sanitized HTML' do
      post '/api/v1/pages', params: {
        title: 'Markdown page',
        name: 'markdown-page',
        content: [{
          id: 'body',
          type: 'text',
          text: "## Heading\n\n**Bold** <script>alert(1)</script> ![image](https://example.com/image.png)",
          format: 'markdown',
        }],
      }, headers: headers, as: :json

      expect(response).to have_http_status(200)
      expect(Page.last.content.first).to include('format' => 'markdown')
      expect(response.parsed_body.dig(:content, 0, :format)).to eq('markdown')
      expect(response.parsed_body.dig(:content, 0, :html)).to include('<h2>Heading</h2>', '<strong>Bold</strong>')
      expect(response.parsed_body.dig(:content, 0, :html)).to_not include('<script', '<img')
    end

    it 'rejects unsupported text formats' do
      post '/api/v1/pages', params: {
        title: 'Invalid page',
        name: 'invalid-format',
        content: [{ id: 'body', type: 'text', text: 'text', format: 'html' }],
      }, headers: headers, as: :json

      expect(response).to have_http_status(422)
      expect(Page).to_not exist(name: 'invalid-format')
    end
  end

  describe 'GET /api/v1/pages/categories' do
    before do
      Fabricate(:page, account: user.account, category: 'Guides')
      Fabricate(:page, account: user.account, category: 'Guides')
      Fabricate(:page, account: user.account, category: 'Stories')
      Fabricate(:page, account: user.account, category: nil)
      Fabricate(:page, category: 'Other account')
    end

    it 'returns the current account categories without duplicates' do
      get '/api/v1/pages/categories', headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to contain_exactly('Guides', 'Stories')
    end
  end

  describe 'page list pagination' do
    before do
      user.update!(role: Fabricate(:user_role, daily_page_limit: 100))
      21.times { Fabricate(:page, account: user.account) }
    end

    it 'returns owner pages in batches of 20' do
      get '/api/v1/pages', headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body.size).to eq(20)

      get '/api/v1/pages', params: { offset: 20 }, headers: headers

      expect(response.parsed_body.size).to eq(1)
    end

    it 'returns public account pages in batches of 20' do
      get "/api/v1/accounts/#{user.account_id}/pages"

      expect(response).to have_http_status(200)
      expect(response.parsed_body.size).to eq(20)

      get "/api/v1/accounts/#{user.account_id}/pages", params: { offset: 20 }

      expect(response.parsed_body.size).to eq(1)
    end
  end

  describe 'search-engine access' do
    let!(:page) { Fabricate(:page, account: user.account) }
    let(:crawler_headers) { { 'User-Agent' => 'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)' } }

    it 'hides page details and lists from crawlers when the owner disables indexing' do
      user.settings['noindex'] = true
      user.save!

      get "/api/v1/pages/#{page.id}", headers: crawler_headers
      expect(response).to have_http_status(404)

      get "/api/v1/accounts/#{user.account_id}/pages", headers: crawler_headers
      expect(response).to have_http_status(200)
      expect(response.parsed_body).to be_empty
    end

    it 'allows crawlers when the owner explicitly enables indexing' do
      user.settings['noindex'] = false
      user.save!

      get "/api/v1/pages/#{page.id}", headers: crawler_headers

      expect(response).to have_http_status(200)
    end

    it 'does not restrict an authenticated reader based on User-Agent' do
      user.settings['noindex'] = true
      user.save!

      get "/api/v1/pages/#{page.id}", headers: headers.merge(crawler_headers)

      expect(response).to have_http_status(200)
    end
  end

  describe 'public response caching' do
    let!(:page) { Fabricate(:page, account: user.account, likes_count: 1) }

    it 'caches anonymous public page reads', :aggregate_failures do
      [
        "/api/v1/pages/#{page.id}",
        "/api/v1/accounts/#{page.account_id}/pages",
        "/api/v1/accounts/#{page.account_id}/pages/#{page.name}",
      ].each do |path|
        get path

        expect(response).to have_http_status(200)
        expect(response.headers['Cache-Control']).to include(
          'public',
          'max-age=15',
          'stale-while-revalidate=30',
          'stale-if-error=86400'
        )
        expect(response.headers['Vary']).to include('Authorization')
        expect(response.headers['X-RateLimit-Limit']).to_not eq('60')
        expect(response.cache_control).to_not include(:private, :no_store)
      end
    end

    it 'keeps authenticated page reads private', :aggregate_failures do
      get "/api/v1/pages/#{page.id}", headers: headers

      expect(response).to have_http_status(200)
      expect(response.cache_control).to include(private: true, no_store: true)
      expect(response.cache_control).to_not include(:public)
    end

    it 'requires authentication for featured pages', :aggregate_failures do
      get '/api/v1/pages/featured'

      expect(response).to have_http_status(401)
      expect(response.cache_control).to include(private: true, no_store: true)
      expect(response.cache_control).to_not include(:public)
    end

    it 'returns featured pages to authenticated users without public caching', :aggregate_failures do
      get '/api/v1/pages/featured', headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to include(page.id.to_s)
      expect(response.cache_control).to include(private: true, no_store: true)
      expect(response.cache_control).to_not include(:public)
    end

    it 'keeps page creation responses private', :aggregate_failures do
      post '/api/v1/pages', params: {
        title: 'New public page',
        name: 'new-public-page',
        content: [],
      }, headers: headers

      expect(response).to have_http_status(200)
      expect(response.cache_control).to include(private: true, no_store: true)
      expect(response.cache_control).to_not include(:public)
    end
  end

  describe 'anonymous page view limits' do
    let!(:page) { Fabricate(:page, account: user.account) }
    let(:remote_ip) { '192.0.2.10' }
    let(:request_headers) { { 'REMOTE_ADDR' => remote_ip } }

    def page_view_limiter(page, remote_ip)
      identity = Api::AnonymousPageViewLimit::RateLimitIdentity.new("#{remote_ip}:#{page.id}")
      RateLimiter.new(identity, family: :anonymous_page_views)
    end

    it 'shares the per-page budget between ID and account slug routes', :aggregate_failures do
      59.times { page_view_limiter(page, remote_ip).record! }

      get "/api/v1/pages/#{page.id}", headers: request_headers
      expect(response).to have_http_status(200)

      get "/api/v1/accounts/#{page.account_id}/pages/#{page.name}", headers: request_headers
      expect(response).to have_http_status(429)
      expect(response.headers['Retry-After'].to_i).to be_positive
      expect(response.cache_control).to include(private: true, no_store: true)
    end

    it 'keeps budgets separate for different pages' do
      other_page = Fabricate(:page, account: user.account)
      60.times { page_view_limiter(page, remote_ip).record! }

      get "/api/v1/pages/#{other_page.id}", headers: request_headers

      expect(response).to have_http_status(200)
    end

    it 'does not apply the anonymous budget to authenticated readers' do
      60.times { page_view_limiter(page, remote_ip).record! }

      get "/api/v1/pages/#{page.id}", headers: headers.merge(request_headers)

      expect(response).to have_http_status(200)
    end

    it 'does not expose or rate limit private pages for anonymous readers' do
      private_page = Fabricate(:page, account: user.account, draft: true)

      get "/api/v1/pages/#{private_page.id}", headers: request_headers

      expect(response).to have_http_status(404)
      expect(page_view_limiter(private_page, remote_ip).to_headers['X-RateLimit-Remaining']).to eq('60')
    end

    it 'normalizes IPv6 clients to a /64 prefix' do
      normalized_ip = '2001:db8::'
      60.times { page_view_limiter(page, normalized_ip).record! }

      get "/api/v1/pages/#{page.id}", headers: { 'REMOTE_ADDR' => '2001:db8::1234' }

      expect(response).to have_http_status(429)
    end

    it 'enforces a global anonymous Pages budget without consuming the page budget on rejection' do
      global_identity = Api::AnonymousPageViewLimit::RateLimitIdentity.new(remote_ip)
      global_limiter = RateLimiter.new(global_identity, family: :anonymous_pages)
      RateLimiter::FAMILIES[:anonymous_pages][:limit].times { global_limiter.record! }

      get "/api/v1/pages/#{page.id}", headers: request_headers

      expect(response).to have_http_status(429)
      expect(page_view_limiter(page, remote_ip).to_headers['X-RateLimit-Remaining']).to eq('60')
    end
  end

  describe 'page list summaries' do
    let!(:page) do
      Fabricate(
        :page,
        account: user.account,
        content: [{ 'id' => 'body', 'type' => 'text', 'text' => 'Large body' }]
      )
    end

    it 'omits page bodies from public account lists but keeps them in detail responses', :aggregate_failures do
      get "/api/v1/accounts/#{user.account_id}/pages"
      expect(response.parsed_body.first).to include(content: [], attached_media: [])

      get "/api/v1/pages/#{page.id}"
      expect(response.parsed_body.dig(:content, 0, :text)).to eq('Large body')
    end

    it 'omits page bodies from owner lists' do
      get '/api/v1/pages', headers: headers

      expect(response.parsed_body.first).to include(content: [], attached_media: [])
    end
  end

  describe 'content limits' do
    it 'preserves the image no-upscale option' do
      post '/api/v1/pages', params: {
        title: 'Original image size',
        name: 'original-image-size',
        content: [{ id: 'image', type: 'image', fileId: nil, noUpscale: true }],
      }, headers: headers, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body.dig(:content, 0, :noUpscale)).to be true
      expect(Page.find_by!(name: 'original-image-size').content.dig(0, 'noUpscale')).to be true
    end

    it 'normalizes spoilers only for text and image blocks' do
      post '/api/v1/pages', params: {
        title: 'Spoiler blocks',
        name: 'spoiler-blocks',
        content: [
          { id: 'text', type: 'text', text: 'Hidden text', spoiler: 'true' },
          { id: 'image', type: 'image', fileId: nil, spoiler: true },
          { id: 'section', type: 'section', title: 'Section', spoiler: true, children: [] },
          { id: 'note', type: 'note', note: nil, spoiler: true },
        ],
      }, headers: headers, as: :json

      expect(response).to have_http_status(200)
      content = response.parsed_body[:content]
      expect(content[0]).to include(type: 'text', spoiler: true)
      expect(content[1]).to include(type: 'image', spoiler: true)
      expect(content[2]).to_not have_key(:spoiler)
      expect(content[3]).to_not have_key(:spoiler)
      expect(Page.find_by!(name: 'spoiler-blocks').content).to eq(content.map(&:deep_stringify_keys))
    end

    it 'rejects content deeper than the server traversal budget' do
      root = { type: 'section', children: [] }
      current = root
      Page::MAX_BLOCK_DEPTH.times do
        child = { type: 'section', children: [] }
        current[:children] = [child]
        current = child
      end

      post '/api/v1/pages', params: { title: 'Deep', name: 'deep', content: [root] }, headers: headers, as: :json

      expect(response).to have_http_status(422)
      expect(Page).to_not exist(name: 'deep')
    end

    it 'limits external-resource blocks when rendering legacy content' do
      page = Fabricate(:page, account: user.account)
      page.update_column(
        :content,
        Array.new(Page::BLOCK_TYPE_LIMITS['note'] + 2) { |index| { type: 'note', note: index.to_s } }
      )

      get "/api/v1/pages/#{page.id}"

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:content].size).to eq(Page::BLOCK_TYPE_LIMITS['note'])
    end
  end

  describe 'password visibility' do
    let(:header_media) { Fabricate(:media_attachment, account: user.account) }
    let!(:password_page) do
      Fabricate(:page, account: user.account, visibility: 'password', access_password: 'correct-password', content: [{ 'id' => 'secret', 'type' => 'text', 'text' => 'Hidden body' }], eye_catching_media_attachment: header_media)
    end

    it 'uses the Mastodon Devise encryptor and does not store the plaintext password' do
      expect(password_page.access_password_digest).to start_with('$2')
      expect(password_page.access_password_digest).to_not include('correct-password')
      expect(password_page.valid_access_password?('correct-password')).to be true
    end

    it 'creates a protected page through the REST API' do
      expect do
        post '/api/v1/pages', params: {
          title: 'Protected page',
          name: 'protected-page',
          visibility: 'password',
          password: 'another-password',
          content: [],
        }, headers: headers
      end.to change(Page.where(visibility: 'password'), :count).by(1)

      expect(Page.find_by!(name: 'protected-page').valid_access_password?('another-password')).to be true
    end

    it 'keeps the existing password when an edit omits it' do
      put "/api/v1/pages/#{password_page.id}", params: { title: 'Updated', visibility: 'password' }, headers: headers

      expect(response).to have_http_status(200)
      expect(password_page.reload.valid_access_password?('correct-password')).to be true
    end

    it 'clears the password when changing visibility' do
      put "/api/v1/pages/#{password_page.id}", params: { visibility: 'public' }, headers: headers

      expect(response).to have_http_status(200)
      expect(password_page.reload.access_password_digest).to be_nil
    end

    it 'lists locked metadata without protected content' do
      get "/api/v1/accounts/#{user.account_id}/pages"

      result = response.parsed_body.find { |page| page[:id] == password_page.id.to_s }
      expect(result).to include('visibility' => 'password', 'locked' => true, 'content' => [], 'attached_media' => [])
      expect(result).to include('eye_catching_media_attachment_id' => header_media.id.to_s)
      expect(result.dig(:eye_catching_media_attachment, :id)).to eq(header_media.id.to_s)
    end

    it 'hides protected header media outside page lists' do
      get "/api/v1/pages/#{password_page.id}"

      expect(response.parsed_body).to include('locked' => true, 'eye_catching_media_attachment_id' => nil, 'eye_catching_media_attachment' => nil)
    end

    it 'rejects a wrong password' do
      post "/api/v1/pages/#{password_page.id}/unlock", params: { password: 'wrong-password' }

      expect(response).to have_http_status(403)
    end

    it 'returns the page and a reusable access token for the correct password' do
      post "/api/v1/pages/#{password_page.id}/unlock", params: { password: 'correct-password' }

      expect(response).to have_http_status(200)
      expect(response.parsed_body.dig(:page, :locked)).to be false
      expect(response.parsed_body.dig(:page, :content, 0, :text)).to eq('Hidden body')

      token = response.parsed_body[:access_token]
      post "/api/v1/pages/#{password_page.id}/unlock", params: { access_token: token }
      expect(response).to have_http_status(200)
    end

    it 'invalidates an access token when the page changes' do
      post "/api/v1/pages/#{password_page.id}/unlock", params: { password: 'correct-password' }
      token = response.parsed_body[:access_token]

      put "/api/v1/pages/#{password_page.id}", params: { title: 'Changed' }, headers: headers
      post "/api/v1/pages/#{password_page.id}/unlock", params: { access_token: token }

      expect(response).to have_http_status(403)
    end

    it 'excludes password pages from featured pages' do
      password_page.update_column(:likes_count, 10)
      get '/api/v1/pages/featured', headers: headers

      expect(response.parsed_body.pluck(:id)).to_not include(password_page.id.to_s)
    end
  end

  describe 'authenticated visibility' do
    let!(:authenticated_page) { Fabricate(:page, account: user.account, visibility: 'authenticated', likes_count: 10) }
    let(:other_user) { Fabricate(:user) }
    let(:other_token) { Fabricate(:accessible_access_token, resource_owner_id: other_user.id, scopes: scopes) }
    let(:other_headers) { { 'Authorization' => "Bearer #{other_token.token}" } }

    it 'hides the page and account listing entry from anonymous users' do
      get "/api/v1/pages/#{authenticated_page.id}"
      expect(response).to have_http_status(404)

      get "/api/v1/accounts/#{user.account_id}/pages"
      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to_not include(authenticated_page.id.to_s)
    end

    it 'allows signed-in users to view the page and account listing entry' do
      get "/api/v1/pages/#{authenticated_page.id}", headers: other_headers
      expect(response).to have_http_status(200)
      expect(response.parsed_body).to include('visibility' => 'authenticated')

      get "/api/v1/accounts/#{user.account_id}/pages", headers: other_headers
      expect(response.parsed_body.pluck(:id)).to include(authenticated_page.id.to_s)
    end

    it 'allows a signed-in user to like the page but excludes it from featured pages' do
      post "/api/v1/pages/#{authenticated_page.id}/like", headers: other_headers
      expect(response).to have_http_status(200)

      get '/api/v1/pages/featured', headers: other_headers
      expect(response.parsed_body.pluck(:id)).to_not include(authenticated_page.id.to_s)
    end
  end

  describe 'main pages' do
    let!(:public_page) { Fabricate(:page, account: user.account) }
    let!(:password_page) do
      Fabricate(:page, account: user.account, visibility: 'password', access_password: 'correct-password')
    end
    let!(:draft_page) { Fabricate(:page, account: user.account, draft: true) }

    it 'only allows public, published pages to be made main pages' do
      post "/api/v1/pages/#{public_page.id}/main", headers: headers
      expect(response).to have_http_status(200)
      expect(public_page.reload.is_main).to be true

      post "/api/v1/pages/#{password_page.id}/main", headers: headers
      expect(response).to have_http_status(404)
      expect(password_page.reload.is_main).to be false

      post "/api/v1/pages/#{draft_page.id}/main", headers: headers
      expect(response).to have_http_status(404)
      expect(draft_page.reload.is_main).to be false
    end
  end

  describe 'GET /api/v1/accounts/:account_id/pages/:name' do
    let(:page) { Fabricate(:page) }

    it 'resolves a public page by its account-scoped slug without authentication' do
      get "/api/v1/accounts/#{page.account_id}/pages/#{page.name}"

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:id]).to eq(page.id.to_s)
    end
  end

  describe 'suspended account visibility' do
    let!(:page) { Fabricate(:page, likes_count: 10) }

    before { page.account.suspend! }

    it 'hides direct, featured, and unlock responses' do
      get "/api/v1/pages/#{page.id}"
      expect(response).to have_http_status(404)

      get '/api/v1/pages/featured', headers: headers
      expect(response.parsed_body.pluck(:id)).to_not include(page.id.to_s)

      post "/api/v1/pages/#{page.id}/unlock", params: { password: 'irrelevant' }
      expect(response).to have_http_status(404)
    end
  end
end
