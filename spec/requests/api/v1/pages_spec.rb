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

  describe 'GET /api/v1/accounts/:account_id/pages/:name' do
    let(:page) { Fabricate(:page) }

    it 'resolves a public page by its account-scoped slug without authentication' do
      get "/api/v1/accounts/#{page.account_id}/pages/#{page.name}"

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:id]).to eq(page.id.to_s)
    end
  end
end
