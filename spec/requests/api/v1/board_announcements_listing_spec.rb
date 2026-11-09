# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Board announcement listing' do
  include_context 'with API authentication', oauth_scopes: 'read:accounts'

  before { Setting.board_announcements_enabled = true }

  def create_announcements(count)
    Array.new(count) { |i| BoardAnnouncement.create!(title: "Notice #{i}", text: 'Body', published: true, published_at: (count - i).minutes.ago) }
  end

  it 'returns every visible announcement without a page parameter' do
    create_announcements(45)

    get '/api/v1/board_announcements', headers: headers

    expect(response).to have_http_status(200)
    expect(response.parsed_body.size).to eq 45
  end

  it 'counts only unread announcements the listing can return' do
    stub_const('Api::V1::BoardAnnouncementsController::INDEX_LIMIT', 2)
    announcements = create_announcements(3)

    get '/api/v1/board_announcements', headers: headers
    listed_ids = response.parsed_body.pluck(:id)

    expect(listed_ids).to eq(announcements.last(2).reverse.map { |a| a.id.to_s })

    get '/api/v1/board_announcements/unread_count', headers: headers

    expect(response.parsed_body[:count]).to eq 2
  end
end
