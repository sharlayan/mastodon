# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat thread muting' do
  let(:user) { Fabricate(:user) }
  let(:account) { user.account }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'write').token }

  before { Setting.misskey_compat_enabled = true }
  after { Setting.misskey_compat_enabled = false }

  it 'rejects duplicate mutes for the same conversation and permits muting again after removal' do
    note = Fabricate(:status)
    reply = Fabricate(:status, thread: note)

    post '/api/notes/thread-muting/create', params: { i: token, noteId: MisskeyCompat::MiId.encode(note.id) }, as: :json
    expect(response).to have_http_status(204)

    post '/api/notes/thread-muting/create', params: { i: token, noteId: MisskeyCompat::MiId.encode(reply.id) }, as: :json
    expect(response).to have_http_status(400)
    expect(response.parsed_body[:error]).to include(code: 'ALREADY_MUTING', id: 'c146e22d-1141-4b31-b28d-176371014d18')
    expect(account.conversation_mutes.where(conversation: note.conversation).count).to eq(1)

    post '/api/notes/thread-muting/delete', params: { i: token, noteId: MisskeyCompat::MiId.encode(note.id) }, as: :json
    expect(response).to have_http_status(204)

    post '/api/notes/thread-muting/create', params: { i: token, noteId: MisskeyCompat::MiId.encode(reply.id) }, as: :json
    expect(response).to have_http_status(204)
    expect(account.conversation_mutes.where(conversation: note.conversation).count).to eq(1)
  end
end
