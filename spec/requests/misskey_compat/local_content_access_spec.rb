# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat local content access settings' do
  let(:author) { Fabricate(:account) }
  let(:remote) { Fabricate(:account, domain: 'remote.example') }
  let(:local_status) { Fabricate(:status, account: author, text: 'Local post') }
  let(:viewer) { Fabricate(:user) }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: viewer.id, scopes: 'read').token }

  def mi(record)
    MisskeyCompat::MiId.encode(record.id)
  end

  before { Setting.misskey_compat_enabled = true }
  after { Setting.misskey_compat_enabled = false }

  context 'when local status pages require sign-in' do
    before { Setting.local_status_page_access = 'authenticated' }

    it 'requires credentials for local notes and hides local replies from anonymous lists' do
      remote_parent = Fabricate(:status, account: remote, text: 'Remote post')
      local_reply = Fabricate(:status, account: author, thread: remote_parent, text: 'Local reply')

      post '/api/notes/show', params: { noteId: mi(local_status) }, as: :json
      expect(response).to have_http_status(401)
      expect(response.parsed_body.dig(:error, :code)).to eq('CREDENTIAL_REQUIRED')

      post '/api/notes/replies', params: { noteId: mi(remote_parent) }, as: :json
      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to_not include(mi(local_reply))

      post '/api/notes/show', params: { i: token, noteId: mi(local_status) }, as: :json
      expect(response).to have_http_status(200)

      post '/api/notes/replies', params: { i: token, noteId: mi(remote_parent) }, as: :json
      expect(response.parsed_body.pluck(:id)).to include(mi(local_reply))
    end
  end

  context 'when local account posts require sign-in' do
    before do
      Setting.local_account_statuses_access = 'authenticated'
      StatusPin.create!(account: author, status: local_status)
    end

    it 'requires credentials for local user notes and hides pinned notes from anonymous profiles' do
      post '/api/users/notes', params: { userId: mi(author) }, as: :json
      expect(response).to have_http_status(401)

      post '/api/users/show', params: { userId: mi(author) }, as: :json
      expect(response).to have_http_status(200)
      expect(response.parsed_body[:pinnedNotes]).to eq([])

      post '/api/users/notes', params: { i: token, userId: mi(author) }, as: :json
      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to include(mi(local_status))

      post '/api/users/show', params: { i: token, userId: mi(author) }, as: :json
      expect(response.parsed_body[:pinnedNoteIds]).to eq([mi(local_status)])
    end

    it 'hides local user notes from signed-in users without feed access when disabled' do
      Setting.local_account_statuses_access = 'disabled'

      post '/api/users/notes', params: { i: token, userId: mi(author) }, as: :json
      expect(response).to have_http_status(404)
      expect(response.parsed_body.dig(:error, :code)).to eq('NO_SUCH_USER')
    end
  end
end
