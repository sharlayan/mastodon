# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat ID translation' do
  let(:user)    { Fabricate(:user) }
  let(:account) { user.account }
  let(:token)   { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write').token }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  describe 'POST /api/i' do
    it 'returns the account id as a 16-char aidx so Aria can parse the id-gen method' do
      post '/api/i', params: { i: token }, as: :json

      expect(response).to have_http_status(200)
      id = response.parsed_body['id']
      expect(id).to match(/\A[0-9a-z]{16}\z/)
      expect(MisskeyCompat::MiId.decode(id)).to eq(account.id.to_s)
    end
  end

  describe 'POST /api/notes/show round-trips an encoded note id' do
    let!(:status) { Fabricate(:status, account: account, text: 'hello') }

    it 'accepts the encoded noteId emitted by the timeline' do
      post '/api/notes/timeline', params: { i: token }, as: :json
      expect(response).to have_http_status(200)

      note = response.parsed_body.first
      expect(note['id']).to match(/\A[0-9a-z]{16}\z/)
      expect(note['userId']).to match(/\A[0-9a-z]{16}\z/)
      expect(MisskeyCompat::MiId.decode(note['id'])).to eq(status.id.to_s)

      # Feed the encoded id straight back as a noteId param.
      post '/api/notes/show', params: { i: token, noteId: note['id'] }, as: :json
      expect(response).to have_http_status(200)
      expect(MisskeyCompat::MiId.decode(response.parsed_body['id'])).to eq(status.id.to_s)
    end
  end

  describe 'timeline pagination with an encoded untilId cursor' do
    let!(:older)  { Fabricate(:status, account: account, text: 'older') }
    let!(:newer)  { Fabricate(:status, account: account, text: 'newer') }

    it 'returns only notes older than the decoded cursor' do
      until_id = MisskeyCompat::MiId.encode(newer.id)
      post '/api/notes/timeline', params: { i: token, untilId: until_id }, as: :json

      expect(response).to have_http_status(200)
      ids = response.parsed_body.map { |n| MisskeyCompat::MiId.decode(n['id']) }
      expect(ids).to include(older.id.to_s)
      expect(ids).to_not include(newer.id.to_s)
    end
  end
end
