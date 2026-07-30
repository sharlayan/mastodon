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
end
