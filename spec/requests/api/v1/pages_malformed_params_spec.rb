# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Pages API with malformed numeric parameters' do
  include_context 'with API authentication', oauth_scopes: 'read write'

  before do
    Setting.pages_enabled = true
    Fabricate(:page, account: user.account, visibility: 'public')
  end

  it 'ignores an array offset on the own page list' do
    get '/api/v1/pages', params: { offset: ['1'] }, headers: headers

    expect(response).to have_http_status(200)
    expect(response.parsed_body.size).to eq 1
  end

  it 'ignores an array offset on the account page list' do
    get "/api/v1/accounts/#{user.account.id}/pages", params: { offset: ['1'] }, headers: headers

    expect(response).to have_http_status(200)
    expect(response.parsed_body.size).to eq 1
  end

  it 'does not fail on an array days value' do
    get '/api/v1/pages/statistics', params: { days: ['30'] }, headers: headers

    expect(response).to have_http_status(200)
  end
end
