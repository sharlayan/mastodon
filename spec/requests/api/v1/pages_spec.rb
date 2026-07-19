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
        expect(Mastodon::Snowflake.to_time(page.id)).to be_within(1.second).of(page.created_at)
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

  describe 'content limits' do
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
      get '/api/v1/pages/featured'

      expect(response.parsed_body.pluck(:id)).to_not include(password_page.id.to_s)
    end

    context 'when community mode is enabled' do
      let!(:other_password_page) do
        Fabricate(:page, visibility: 'password', access_password: 'correct-password', content: [{ 'id' => 'secret', 'type' => 'text', 'text' => 'Moderated body' }])
      end
      let(:top_position) { (UserRole.assignable.maximum(:position) || 0) + 1 }

      it 'allows the owner role to read protected content without a password' do
        user.update!(role: Fabricate(:user_role, position: top_position, permissions: UserRole::FLAGS[:administrator]))

        ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') do
          get "/api/v1/pages/#{other_password_page.id}", headers: headers
        end

        expect(response).to have_http_status(200)
        expect(response.parsed_body[:locked]).to be false
        expect(response.parsed_body.dig(:content, 0, :text)).to eq('Moderated body')
      end

      it 'keeps protected content locked for the owner role outside community mode' do
        user.update!(role: Fabricate(:user_role, position: top_position, permissions: UserRole::FLAGS[:administrator]))

        ClimateControl.modify(OC_ROLEPLAY_OPTION: 'false') do
          get "/api/v1/pages/#{other_password_page.id}", headers: headers
        end

        expect(response).to have_http_status(200)
        expect(response.parsed_body).to include('locked' => true, 'content' => [], 'attached_media' => [])
      end

      it 'keeps protected content locked for an administrator below the owner role' do
        administrator_role = Fabricate(:user_role, position: top_position, permissions: UserRole::FLAGS[:administrator])
        Fabricate(:user_role, position: top_position + 1, permissions: UserRole::FLAGS[:administrator])
        user.update!(role: administrator_role)

        ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') do
          get "/api/v1/pages/#{other_password_page.id}", headers: headers
        end

        expect(response).to have_http_status(200)
        expect(response.parsed_body).to include('locked' => true, 'content' => [], 'attached_media' => [])
      end
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

      get '/api/v1/pages/featured'
      expect(response.parsed_body.pluck(:id)).to_not include(page.id.to_s)

      post "/api/v1/pages/#{page.id}/unlock", params: { password: 'irrelevant' }
      expect(response).to have_http_status(404)
    end
  end
end
