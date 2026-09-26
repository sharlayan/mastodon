# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat notes/children endpoint' do
  let(:user)  { Fabricate(:user) }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read').token }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  it 'returns only direct replies when a remote note has multiple reply branches' do
    remote_account = Fabricate(:account, domain: 'remote.example')
    root = Fabricate(:status, account: remote_account, text: 'post 1')
    reply_one = Fabricate(:status, account: remote_account, text: 'reply 1', thread: root)
    reply_two = Fabricate(:status, account: user.account, text: 'reply 2', thread: root)
    nested_reply = Fabricate(:status, account: remote_account, text: 'reply 3', thread: reply_one)
    deeply_nested_reply = Fabricate(:status, account: remote_account, text: 'reply 4', thread: nested_reply)

    post '/api/notes/children', params: { i: token, noteId: MisskeyCompat::MiId.encode(root.id) }, as: :json

    expect(response).to have_http_status(200)
    returned_ids = response.parsed_body.pluck('id').map { |id| MisskeyCompat::MiId.decode(id) }
    expect(returned_ids).to contain_exactly(reply_one.id.to_s, reply_two.id.to_s)
    expect(returned_ids).to_not include(nested_reply.id.to_s, deeply_nested_reply.id.to_s)

    post '/api/notes/children', params: { i: token, noteId: MisskeyCompat::MiId.encode(reply_one.id) }, as: :json

    expect(response).to have_http_status(200)
    returned_ids = response.parsed_body.pluck('id').map { |id| MisskeyCompat::MiId.decode(id) }
    expect(returned_ids).to contain_exactly(nested_reply.id.to_s)
    expect(returned_ids).to_not include(deeply_nested_reply.id.to_s)
  end

  it 'includes non-pure renotes but leaves pure renotes to notes/renotes' do
    root = Fabricate(:status)
    pure_renote = Fabricate(:status, reblog: root, text: '')
    quote_renote = Fabricate(:status, reblog: root, text: 'commentary')

    post '/api/notes/children', params: { i: token, noteId: MisskeyCompat::MiId.encode(root.id) }, as: :json

    returned_ids = response.parsed_body.pluck(:id)
    expect(returned_ids).to include(MisskeyCompat::MiId.encode(quote_renote.id))
    expect(returned_ids).to_not include(MisskeyCompat::MiId.encode(pure_renote.id))
  end

  it 'includes visible accepted content quotes once and fills the page past hidden quotes' do
    root = Fabricate(:status)
    accepted = Fabricate(:quote, quoted_status: root, status: Fabricate(:status, text: 'quoted'), state: :accepted)
    Fabricate(:quote, quoted_status: root, status: Fabricate(:status, text: 'pending'), state: :pending)
    Fabricate(:quote, quoted_status: root, status: Fabricate(:status, text: 'private', visibility: :private), state: :accepted)
    write_token = Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'write').token
    post '/api/notes/create', params: { i: write_token, renoteId: MisskeyCompat::MiId.encode(root.id), cw: 'CW' }, as: :json
    cw_only_id = response.parsed_body.dig(:createdNote, :id)
    reply = Fabricate(:status, account: user.account, text: 'reply and quote', in_reply_to_id: root.id, in_reply_to_account_id: root.account_id)
    Fabricate(:quote, quoted_status: root, status: reply, state: :accepted)

    post '/api/notes/children', params: { i: token, noteId: MisskeyCompat::MiId.encode(root.id), limit: 2 }, as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body.pluck(:id)).to eq([MisskeyCompat::MiId.encode(reply.id), MisskeyCompat::MiId.encode(accepted.status_id)])
    expect(response.parsed_body.pluck(:id)).to_not include(cw_only_id)
  end
end
