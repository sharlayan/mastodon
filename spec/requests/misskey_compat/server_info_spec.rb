# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat server-info endpoint' do
  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  it 'returns the privacy-preserving Misskey server information shape' do
    get '/api/server-info'

    expect(response).to have_http_status(200)
    expect(response.parsed_body).to eq(
      'machine' => '?',
      'cpu' => {
        'model' => '?',
        'cores' => 0,
      },
      'mem' => {
        'total' => 0,
      },
      'fs' => {
        'total' => 0,
        'used' => 0,
      }
    )
  end

  it 'advertises server-info' do
    post '/api/endpoints', as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body).to include('server-info')
  end
end
