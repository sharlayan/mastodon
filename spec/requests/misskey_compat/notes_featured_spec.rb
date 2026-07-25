# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat notes/featured endpoint' do
  before do
    Setting.misskey_compat_enabled = true
    Setting.trends = true
  end

  after do
    Setting.misskey_compat_enabled = false
    Setting.trends = false
  end

  it 'returns Mastodon trending statuses instead of the latest local statuses' do
    trending = Fabricate(:status)
    recent = Fabricate(:status)
    Fabricate(:status_trend, status: trending, account: trending.account, allowed: true, score: 10)

    post '/api/notes/featured', params: {}, as: :json

    expect(response).to have_http_status(200)
    returned_ids = response.parsed_body.pluck('id').map { |id| MisskeyCompat::MiId.decode(id) }
    expect(returned_ids).to eq([trending.id.to_s])
    expect(returned_ids).to_not include(recent.id.to_s)
  end

  it 'returns an empty list when Mastodon trends are disabled' do
    Setting.trends = false

    post '/api/notes/featured', params: {}, as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body).to eq([])
  end
end
