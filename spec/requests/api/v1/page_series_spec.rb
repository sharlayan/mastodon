# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Page series' do
  include_context 'with API authentication', oauth_scopes: 'read write read:accounts write:accounts'

  before { Setting.pages_enabled = true }

  it 'creates, lists, updates, and deletes an owned series' do
    cover = Fabricate(:media_attachment, account: user.account)
    post '/api/v1/page_series', params: { title: ' Guides ', description: 'A collection', cover_media_attachment_id: cover.id, displayed: false }, headers: headers
    expect(response).to have_http_status(200)
    series_id = response.parsed_body[:id]
    expect(response.parsed_body).to include(
      title: 'Guides',
      description: 'A collection',
      displayed: false,
      cover_media_attachment_id: cover.id.to_s,
      pages_count: 0
    )
    expect(response.parsed_body.dig(:cover_media_attachment, :id)).to eq(cover.id.to_s)

    get '/api/v1/page_series', headers: headers
    expect(response.parsed_body.pluck(:id)).to contain_exactly(series_id)

    put "/api/v1/page_series/#{series_id}", params: { title: 'Manuals', displayed: true }, headers: headers
    expect(response).to have_http_status(200)
    expect(response.parsed_body[:title]).to eq('Manuals')
    expect(response.parsed_body[:displayed]).to be true

    page = Fabricate(:page, account: user.account, page_series_id: series_id)
    delete "/api/v1/page_series/#{series_id}", headers: headers
    expect(response).to have_http_status(200)
    expect(PageSeries).to_not exist(series_id)
    expect(page.reload.page_series).to be_nil
  end

  it 'rejects cover media owned by another account' do
    cover = Fabricate(:media_attachment)

    post '/api/v1/page_series', params: { title: 'Guides', cover_media_attachment_id: cover.id }, headers: headers

    expect(response).to have_http_status(422)
  end

  it 'rejects a non-Drive cover when pages are limited to Drive files' do
    Setting.pages_drive_only = true
    cover = Fabricate(:media_attachment, account: user.account)

    post '/api/v1/page_series', params: { title: 'Guides', cover_media_attachment_id: cover.id }, headers: headers

    expect(response).to have_http_status(422)
  end

  it 'lists public Booklets from other accounts' do
    other_account = Fabricate(:account)
    booklet = Fabricate(:page_series, account: other_account, title: 'Public guide')
    representative = Fabricate(
      :page,
      account: other_account,
      page_series: booklet,
      name: 'guide',
      visibility: 'public'
    )
    booklet.update!(main_page: representative)

    own_booklet = Fabricate(:page_series, account: user.account)
    own_page = Fabricate(:page, account: user.account, page_series: own_booklet, visibility: 'public')
    own_booklet.update!(main_page: own_page)

    private_booklet = Fabricate(:page_series, account: other_account)
    private_page = Fabricate(:page, account: other_account, page_series: private_booklet, visibility: 'private')
    private_booklet.update_column(:main_page_id, private_page.id)

    get '/api/v1/page_series/others', headers: headers

    expect(response).to have_http_status(200)
    expect(response.parsed_body.pluck(:id)).to contain_exactly(booklet.id.to_s)
    expect(response.parsed_body.first).to include(
      account_id: other_account.id.to_s,
      main_page_name: 'guide',
      entry_page_id: representative.id.to_s,
      entry_page_name: 'guide',
      pages_count: 1
    )
    expect(response.parsed_body.first.dig(:account, :id)).to eq(other_account.id.to_s)
  end

  it 'uses the oldest public page to open a Booklet without a representative page' do
    other_account = Fabricate(:account)
    booklet = Fabricate(:page_series, account: other_account, title: 'Public guide')
    Fabricate(:page, account: other_account, page_series: booklet, name: 'newer', visibility: 'public', created_at: 1.day.ago)
    oldest_page = Fabricate(:page, account: other_account, page_series: booklet, name: 'oldest', visibility: 'public', created_at: 2.days.ago)
    Fabricate(:page, account: other_account, page_series: booklet, name: 'private', visibility: 'private', created_at: 3.days.ago)

    get '/api/v1/page_series/others', headers: headers

    expect(response).to have_http_status(200)
    expect(response.parsed_body.find { |item| item[:id] == booklet.id.to_s }).to include(
      main_page_id: nil,
      main_page_name: nil,
      entry_page_id: oldest_page.id.to_s,
      entry_page_name: 'oldest'
    )
    expect(response.parsed_body.pluck(:id)).to include(booklet.id.to_s)

    get "/api/v1/accounts/#{other_account.id}/page_series"

    expect(response).to have_http_status(200)
    expect(response.parsed_body.find { |item| item[:id] == booklet.id.to_s }).to include(
      entry_page_id: oldest_page.id.to_s,
      entry_page_name: 'oldest'
    )
  end

  it 'excludes privately displayed Booklets from the public bookcase but includes them on the owner profile' do
    other_account = Fabricate(:account)
    booklet = Fabricate(:page_series, account: other_account, displayed: false)
    representative = Fabricate(:page, account: other_account, page_series: booklet, visibility: 'public')
    booklet.update!(main_page: representative)

    get '/api/v1/page_series/others', headers: headers
    expect(response.parsed_body.pluck(:id)).to_not include(booklet.id.to_s)

    get "/api/v1/accounts/#{other_account.id}/page_series"
    expect(response).to have_http_status(200)
    expect(response.parsed_body.pluck(:id)).to include(booklet.id.to_s)
    expect(response.parsed_body.first[:displayed]).to be false
  end

  it 'assigns pages, orders them, and selects a public representative page' do
    cover = Fabricate(:media_attachment, account: user.account)
    series = Fabricate(:page_series, account: user.account, cover_media_attachment: cover)
    page = Fabricate(:page, account: user.account)

    put "/api/v1/pages/#{page.id}", params: { booklet_id: series.id, booklet_position: 3 }, headers: headers
    expect(response).to have_http_status(200)
    expect(response.parsed_body).to include(
      booklet_id: series.id.to_s,
      booklet_position: 3,
      booklet_main: false
    )
    expect(response.parsed_body.dig(:booklet, :title)).to eq(series.title)
    expect(response.parsed_body.dig(:booklet, :cover_media_attachment, :id)).to eq(cover.id.to_s)

    post "/api/v1/pages/#{page.id}/series_main", headers: headers
    expect(response).to have_http_status(200)
    expect(response.parsed_body[:booklet_main]).to be true
    expect(series.reload.main_page).to eq(page)

    delete "/api/v1/pages/#{page.id}/series_main", headers: headers
    expect(response).to have_http_status(200)
    expect(series.reload.main_page).to be_nil
  end

  it 'moves the representative page to the front while preserving the remaining order' do
    series = Fabricate(:page_series, account: user.account)
    first_page = Fabricate(:page, account: user.account, page_series: series, series_position: 0)
    second_page = Fabricate(:page, account: user.account, page_series: series, series_position: 2)
    representative = Fabricate(:page, account: user.account, page_series: series, series_position: 3)

    post "/api/v1/pages/#{representative.id}/series_main", headers: headers

    expect(response).to have_http_status(200)
    expect(response.parsed_body).to include(booklet_main: true, booklet_position: 0)
    expect(series.reload.main_page).to eq(representative)
    expect(series.pages.reload.pluck(:id, :series_position)).to eq(
      [
        [representative.id, 0],
        [first_page.id, 1],
        [second_page.id, 2],
      ]
    )
  end

  it 'rejects another account series and non-public representative pages' do
    other_series = Fabricate(:page_series)
    page = Fabricate(:page, account: user.account, visibility: 'private')

    put "/api/v1/pages/#{page.id}", params: { booklet_id: other_series.id }, headers: headers
    expect(response).to have_http_status(422)

    own_series = Fabricate(:page_series, account: user.account)
    page.update!(page_series: own_series)
    post "/api/v1/pages/#{page.id}/series_main", headers: headers
    expect(response).to have_http_status(404)
  end

  it 'does not allow another account to mutate a series' do
    series = Fabricate(:page_series)

    put "/api/v1/page_series/#{series.id}", params: { title: 'Stolen' }, headers: headers

    expect(response).to have_http_status(404)
    expect(series.reload.title).to_not eq('Stolen')
  end
end
