# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Profile birthday' do
  let(:user) { Fabricate(:user) }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write') }
  let(:other_token) { Fabricate(:accessible_access_token, resource_owner_id: Fabricate(:user).id, scopes: 'read') }
  let(:headers) { { 'Authorization' => "Bearer #{token.token}" } }
  let(:other_headers) { { 'Authorization' => "Bearer #{other_token.token}" } }

  before { travel_to(Time.zone.local(2026, 11, 12, 9)) }

  it 'stores the birthday and its visibility, and shows it to others only when public' do
    patch '/api/v1/profile', headers: headers, params: { birthday: '1990-12-31', show_birthday: false }

    expect(response).to have_http_status(200)
    expect(response.parsed_body).to include(birthday: '1990-12-31', show_birthday: false)

    get "/api/v1/accounts/#{user.account_id}", headers: headers
    expect(response.parsed_body[:birthday]).to eq('1990-12-31')

    get "/api/v1/accounts/#{user.account_id}", headers: other_headers
    expect(response.parsed_body).to_not have_key(:birthday)

    patch '/api/v1/profile', headers: headers, params: { show_birthday: true }
    expect(response.parsed_body).to include(birthday: '1990-12-31', show_birthday: true)

    get "/api/v1/accounts/#{user.account_id}", headers: other_headers
    expect(response.parsed_body[:birthday]).to eq('1990-12-31')

    get "/api/v1/accounts/#{user.account_id}"
    expect(response.parsed_body[:birthday]).to eq('1990-12-31')
  end

  it 'rejects impossible or future dates and clears the birthday with a blank value' do
    %w(1990-02-30 2999-01-01 12/31).each do |invalid|
      patch '/api/v1/profile', headers: headers, params: { birthday: invalid }
      expect(response).to have_http_status(422)
    end

    patch '/api/v1/profile', headers: headers, params: { birthday: '2000-02-29' }
    expect(user.account.reload.birthday).to eq('2000-02-29')

    patch '/api/v1/profile', headers: headers, params: { birthday: '' }
    expect(response.parsed_body[:birthday]).to be_nil
    expect(user.account.reload.birthday).to be_nil
  end
end
