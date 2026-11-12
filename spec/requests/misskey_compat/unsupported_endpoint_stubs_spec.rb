# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat unsupported endpoint stubs' do
  let(:object_endpoints) do
    %w(
      test
      v2/admin/emoji/list
    )
  end

  let(:array_endpoints) do
    %w(
      bubble-game/ranking
    )
  end

  let(:void_endpoints) do
    %w(
      bubble-game/register
      promo/read
    )
  end

  let(:explicitly_unsupported_endpoints) do
    %w(
      admin/accounts/create
      admin/accounts/delete
      admin/delete-account
      admin/send-email
      i/export-antennas
      i/export-favorites
      i/import-antennas
      reset-db
    )
  end

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  it 'returns an empty object, an empty array, or no content from every object, array, and void stub' do
    object_endpoints.each do |endpoint|
      post "/api/#{endpoint}", as: :json

      expect(response).to have_http_status(200), endpoint
      expect(response.parsed_body).to eq({}), endpoint
    end

    array_endpoints.each do |endpoint|
      post "/api/#{endpoint}", as: :json

      expect(response).to have_http_status(200), endpoint
      expect(response.parsed_body).to eq([]), endpoint
    end

    void_endpoints.each do |endpoint|
      post "/api/#{endpoint}", as: :json

      expect(response).to have_http_status(204), endpoint
      expect(response.body).to be_empty, endpoint
    end
  end

  it 'returns a Misskey error envelope from explicitly unsupported endpoints' do
    explicitly_unsupported_endpoints.each do |endpoint|
      post "/api/#{endpoint}", as: :json

      expect(response).to have_http_status(501)
      expect(response.parsed_body[:error]).to include(code: 'UNSUPPORTED_ENDPOINT', kind: 'server')
    end
  end

  it 'advertises every named unsupported endpoint stub' do
    post '/api/endpoints', as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body).to include(*(object_endpoints + array_endpoints + void_endpoints + explicitly_unsupported_endpoints))
  end
end
