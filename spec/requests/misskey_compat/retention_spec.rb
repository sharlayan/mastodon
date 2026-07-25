# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat retention' do
  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  it 'returns newest-first aggregations in the Misskey retention shape' do
    Fabricate(:misskey_retention_aggregation, date_key: '2026-07-22', users_count: 2, data: { '2026-07-23' => 1 }, created_at: Time.utc(2026, 7, 22))
    newest = Fabricate(:misskey_retention_aggregation, date_key: '2026-07-23', users_count: 5, data: { '2026-07-24' => 3 }, created_at: Time.utc(2026, 7, 23))

    post '/api/retention', params: {}, as: :json

    expect(response).to have_http_status(200)
    body = response.parsed_body
    expect(body.size).to eq(2)
    expect(body.first[:createdAt]).to eq(newest.created_at.iso8601)
    expect(body.first[:users]).to eq(5)
    expect(body.first[:data]).to eq('2026-07-24' => 3)
  end

  it 'supports GET as well' do
    get '/api/retention'

    expect(response).to have_http_status(200)
  end

  it 'is gated behind Misskey compatibility being enabled' do
    Setting.misskey_compat_enabled = false

    post '/api/retention', params: {}, as: :json

    expect(response).to have_http_status(404)
  end
end
