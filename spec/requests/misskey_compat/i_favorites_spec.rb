# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat i/favorites endpoint' do
  let(:user)    { Fabricate(:user) }
  let(:account) { user.account }
  let(:token)   { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read').token }
  let(:author)  { Fabricate(:account, username: 'author') }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  def favorite_note_ids
    response.parsed_body.map { |favorite| favorite[:noteId] }
  end

  it 'skips favourites whose status has been discarded' do
    kept = Fabricate(:status, account: author)
    discarded = Fabricate(:status, account: author)
    Fabricate(:favourite, account: account, status: kept)
    Fabricate(:favourite, account: account, status: discarded)
    discarded.discard

    post '/api/i/favorites', params: { i: token }, as: :json

    expect(response).to have_http_status(200)
    expect(favorite_note_ids).to eq([MisskeyCompat::MiId.encode(kept.id)])
  end

  it 'skips favourites whose status the viewer can no longer see' do
    visible = Fabricate(:status, account: author)
    hidden = Fabricate(:status, account: Fabricate(:account, username: 'private'), visibility: :private)
    Fabricate(:favourite, account: account, status: visible)
    Favourite.new(account: account, status: hidden).save!(validate: false)

    post '/api/i/favorites', params: { i: token }, as: :json

    expect(response).to have_http_status(200)
    expect(favorite_note_ids).to eq([MisskeyCompat::MiId.encode(visible.id)])
  end
end
