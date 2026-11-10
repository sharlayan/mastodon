# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Board announcement authorization' do
  include_context 'with API authentication', oauth_scopes: 'read:accounts'

  let(:announcement) { BoardAnnouncement.create!(title: 'Notice', text: 'Body', published: true) }
  let(:paths) do
    {
      index: '/api/v1/board_announcements',
      show: "/api/v1/board_announcements/#{announcement.id}",
      unread_count: '/api/v1/board_announcements/unread_count',
    }
  end

  before { Setting.board_announcements_enabled = true }

  it 'allows index, show, and unread_count with an authorized token', :aggregate_failures do
    paths.each do |endpoint, path|
      get path, headers: headers

      expect(response).to have_http_status(200), -> { "#{endpoint} returned #{response.status}" }
    end
  end

  context 'with a write-only token' do
    let(:scopes) { 'write:accounts' }

    it 'rejects index, show, and unread_count outside the granted scopes', :aggregate_failures do
      paths.each do |endpoint, path|
        get path, headers: headers

        expect(response).to have_http_status(403), -> { "#{endpoint} returned #{response.status}" }
      end
    end
  end

  it 'rejects index, show, and unread_count without a token or with a revoked or expired token', :aggregate_failures do
    revoked_token = Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: scopes).tap(&:revoke)
    expired_token = Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: scopes, created_at: 2.minutes.ago, expires_in: 1)

    paths.each do |endpoint, path|
      get path
      expect(response).to have_http_status(401), -> { "#{endpoint} without a token returned #{response.status}" }

      get path, headers: { 'Authorization' => "Bearer #{revoked_token.token}" }
      expect(response).to have_http_status(401), -> { "#{endpoint} with a revoked token returned #{response.status}" }

      get path, headers: { 'Authorization' => "Bearer #{expired_token.token}" }
      expect(response).to have_http_status(401), -> { "#{endpoint} with an expired token returned #{response.status}" }
    end
  end

  it 'keeps feature gating for authorized requests' do
    Setting.board_announcements_enabled = false

    get '/api/v1/board_announcements', headers: headers

    expect(response).to have_http_status(404)
  end
end
