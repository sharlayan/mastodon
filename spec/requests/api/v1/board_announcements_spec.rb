# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Board announcement authorization' do
  include_context 'with API authentication', oauth_scopes: 'read:accounts'

  let(:announcement) { BoardAnnouncement.create!(title: 'Notice', text: 'Body', published: true) }

  before { Setting.board_announcements_enabled = true }

  %i(index show unread_count).each do |endpoint|
    describe "GET #{endpoint}" do
      subject(:request_announcement) { get path, headers: headers }

      let(:path) do
        case endpoint
        when :index then '/api/v1/board_announcements'
        when :show then "/api/v1/board_announcements/#{announcement.id}"
        when :unread_count then '/api/v1/board_announcements/unread_count'
        end
      end

      it 'allows reading with an authorized token' do
        request_announcement

        expect(response).to have_http_status(200)
      end

      context 'with a write-only token' do
        let(:scopes) { 'write:accounts' }

        it 'rejects reading outside the granted scopes' do
          request_announcement

          expect(response).to have_http_status(403)
        end
      end

      context 'with a revoked token' do
        before { token.revoke }

        it 'rejects the invalid credential' do
          request_announcement

          expect(response).to have_http_status(401)
        end
      end

      context 'with an expired token' do
        before { token.update!(created_at: 2.minutes.ago, expires_in: 1) }

        it 'rejects the invalid credential' do
          request_announcement

          expect(response).to have_http_status(401)
        end
      end

      context 'without a token' do
        let(:headers) { {} }

        it 'requires an authorized credential' do
          request_announcement

          expect(response).to have_http_status(401)
        end
      end
    end
  end

  it 'keeps feature gating for authorized requests' do
    Setting.board_announcements_enabled = false

    get '/api/v1/board_announcements', headers: headers

    expect(response).to have_http_status(404)
  end
end
