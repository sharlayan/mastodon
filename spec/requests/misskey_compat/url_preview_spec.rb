# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compatible URL preview' do
  before { Setting.misskey_compat_enabled = true }
  after { Setting.misskey_compat_enabled = false }

  it 'returns a preview card found through a status URL association' do
    card = Fabricate(:preview_card, url: 'https://canonical.example/article', title: 'Article')
    status = Fabricate(:status)
    PreviewCardsStatus.create!(preview_card: card, status: status, url: 'https://requested.example/article')

    get '/url', params: { url: 'https://requested.example/article' }

    expect(response).to have_http_status(200)
    expect(response.parsed_body).to include(
      url: 'https://canonical.example/article',
      title: 'Article'
    )
  end

  it 'returns the Misskey URL_PREVIEW_FAILED error for unknown URLs' do
    get '/url', params: { url: 'https://unknown.example/article' }

    expect(response).to have_http_status(422)
    expect(response.parsed_body['error']).to include(
      'code' => 'URL_PREVIEW_FAILED',
      'id' => '09d01cb5-53b9-4856-82e5-38a50c290a3b'
    )
  end

  it 'rejects a non-string url' do
    get '/url', params: { url: ['https://requested.example/article'] }

    expect(response).to have_http_status(400)
  end
end
