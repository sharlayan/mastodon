# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Page series' do
  include_context 'with API authentication', oauth_scopes: 'read write read:accounts write:accounts'

  before { Setting.pages_enabled = true }

  it 'creates, lists, updates, and deletes an owned series' do
    post '/api/v1/page_series', params: { title: ' Guides ', description: 'A collection' }, headers: headers
    expect(response).to have_http_status(200)
    series_id = response.parsed_body[:id]
    expect(response.parsed_body).to include(title: 'Guides', description: 'A collection', pages_count: 0)

    get '/api/v1/page_series', headers: headers
    expect(response.parsed_body.pluck(:id)).to contain_exactly(series_id)

    put "/api/v1/page_series/#{series_id}", params: { title: 'Manuals' }, headers: headers
    expect(response).to have_http_status(200)
    expect(response.parsed_body[:title]).to eq('Manuals')

    page = Fabricate(:page, account: user.account, page_series_id: series_id)
    delete "/api/v1/page_series/#{series_id}", headers: headers
    expect(response).to have_http_status(200)
    expect(PageSeries).to_not exist(series_id)
    expect(page.reload.page_series).to be_nil
  end

  it 'assigns pages, orders them, and selects a public representative page' do
    series = Fabricate(:page_series, account: user.account)
    page = Fabricate(:page, account: user.account)

    put "/api/v1/pages/#{page.id}", params: { page_series_id: series.id, series_position: 3 }, headers: headers
    expect(response).to have_http_status(200)
    expect(response.parsed_body).to include(
      page_series_id: series.id.to_s,
      series_position: 3,
      series_main: false
    )
    expect(response.parsed_body.dig(:page_series, :title)).to eq(series.title)

    post "/api/v1/pages/#{page.id}/series_main", headers: headers
    expect(response).to have_http_status(200)
    expect(response.parsed_body[:series_main]).to be true
    expect(series.reload.main_page).to eq(page)

    delete "/api/v1/pages/#{page.id}/series_main", headers: headers
    expect(response).to have_http_status(200)
    expect(series.reload.main_page).to be_nil
  end

  it 'rejects another account series and non-public representative pages' do
    other_series = Fabricate(:page_series)
    page = Fabricate(:page, account: user.account, visibility: 'private')

    put "/api/v1/pages/#{page.id}", params: { page_series_id: other_series.id }, headers: headers
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
