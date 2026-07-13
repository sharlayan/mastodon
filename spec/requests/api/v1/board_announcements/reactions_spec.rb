# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Board Announcements Reactions' do
  let(:user) { Fabricate(:user) }
  let(:scopes) { 'write:favourites' }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: scopes) }
  let(:headers) { { 'Authorization' => "Bearer #{token.token}" } }
  let(:announcement) { BoardAnnouncement.create!(title: 'Notice', text: 'Body', published: true) }

  before do
    Setting.board_announcements_enabled = true
  end

  describe 'PUT /api/v1/board_announcements/:board_announcement_id/reactions/:id' do
    it 'creates a reaction for a visible announcement', :aggregate_failures do
      put "/api/v1/board_announcements/#{announcement.id}/reactions/#{escaped_emoji}", headers: headers

      expect(response).to have_http_status(200)
      expect(response.content_type).to start_with('application/json')
      expect(announcement.board_announcement_reactions.find_by(name: '😂', account: user.account)).to_not be_nil
    end

    it 'does not create a reaction for an announcement hidden from the account', :aggregate_failures do
      hidden_announcement = BoardAnnouncement.create!(title: 'Hidden', text: 'Body', published: true, published_at: 1.day.ago, for_existing_users: true)

      put "/api/v1/board_announcements/#{hidden_announcement.id}/reactions/#{escaped_emoji}", headers: headers

      expect(response).to have_http_status(404)
      expect(hidden_announcement.board_announcement_reactions.find_by(name: '😂', account: user.account)).to be_nil
    end
  end

  describe 'DELETE /api/v1/board_announcements/:board_announcement_id/reactions/:id' do
    it 'removes a reaction from a visible announcement', :aggregate_failures do
      announcement.board_announcement_reactions.create!(account: user.account, name: '😂')

      delete "/api/v1/board_announcements/#{announcement.id}/reactions/#{escaped_emoji}", headers: headers

      expect(response).to have_http_status(200)
      expect(response.content_type).to start_with('application/json')
      expect(announcement.board_announcement_reactions.find_by(name: '😂', account: user.account)).to be_nil
    end

    it 'does not remove a reaction from an announcement hidden from the account', :aggregate_failures do
      hidden_announcement = BoardAnnouncement.create!(title: 'Hidden', text: 'Body', published: true, published_at: 1.day.ago, for_existing_users: true)
      reaction = hidden_announcement.board_announcement_reactions.create!(account: user.account, name: '😂')

      delete "/api/v1/board_announcements/#{hidden_announcement.id}/reactions/#{escaped_emoji}", headers: headers

      expect(response).to have_http_status(404)
      expect(BoardAnnouncementReaction.exists?(reaction.id)).to be true
    end
  end

  def escaped_emoji
    CGI.escape('😂')
  end
end
