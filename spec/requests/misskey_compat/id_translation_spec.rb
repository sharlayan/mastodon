# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat ID translation' do
  let(:user)    { Fabricate(:user) }
  let(:account) { user.account }
  let(:token)   { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write').token }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  describe 'encoded note ids' do
    let!(:older) { Fabricate(:status, account: account, text: 'older') }
    let!(:newer) { Fabricate(:status, account: account, text: 'newer') }

    it 'round-trips the encoded noteId emitted by the timeline and paginates with an encoded untilId cursor' do
      post '/api/notes/timeline', params: { i: token }, as: :json
      expect(response).to have_http_status(200)

      note = response.parsed_body.first
      expect(note['id']).to match(/\A[0-9a-z]{16}\z/)
      expect(note['userId']).to match(/\A[0-9a-z]{16}\z/)
      expect(MisskeyCompat::MiId.decode(note['id'])).to eq(newer.id.to_s)

      post '/api/notes/show', params: { i: token, noteId: note['id'] }, as: :json
      expect(response).to have_http_status(200)
      expect(MisskeyCompat::MiId.decode(response.parsed_body['id'])).to eq(newer.id.to_s)

      post '/api/notes/timeline', params: { i: token, untilId: MisskeyCompat::MiId.encode(newer.id) }, as: :json

      expect(response).to have_http_status(200)
      ids = response.parsed_body.map { |n| MisskeyCompat::MiId.decode(n['id']) }
      expect(ids).to include(older.id.to_s)
      expect(ids).to_not include(newer.id.to_s)
    end
  end
end
