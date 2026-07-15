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

  describe 'GET /api/v1/accounts/:account_id/pages/:name' do
    let(:page) { Fabricate(:page) }

    it 'resolves a public page by its account-scoped slug without authentication' do
      get "/api/v1/accounts/#{page.account_id}/pages/#{page.name}"

      expect(response).to have_http_status(200)
      expect(response.parsed_body[:id]).to eq(page.id.to_s)
    end
  end
end
