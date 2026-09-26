# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat notes/renotes and notes/unrenote endpoints' do
  let(:user) { Fabricate(:user) }
  let(:account) { user.account }
  let(:root) { Fabricate(:status) }
  let(:read_token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read').token }
  let(:write_token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'write').token }

  before { Setting.misskey_compat_enabled = true }
  after { Setting.misskey_compat_enabled = false }

  it 'lists visible accepted quotes and reblogs while filling past hidden quotes' do
    reblog = Fabricate(:status, reblog: root)
    accepted = Fabricate(:quote, quoted_status: root, status: Fabricate(:status, text: 'quoted'), state: :accepted)
    Fabricate(:quote, quoted_status: root, status: Fabricate(:status, text: 'pending'), state: :pending)
    Fabricate(:quote, quoted_status: root, status: Fabricate(:status, text: 'private', visibility: :private), state: :accepted)
    newest = Fabricate(:quote, quoted_status: root, status: Fabricate(:status, text: 'newest'), state: :accepted)

    post '/api/notes/renotes', params: { i: read_token, noteId: MisskeyCompat::MiId.encode(root.id), limit: 2 }, as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body.pluck(:id)).to eq([MisskeyCompat::MiId.encode(newest.status_id), MisskeyCompat::MiId.encode(accepted.status_id)])

    post '/api/notes/renotes', params: { i: read_token, noteId: MisskeyCompat::MiId.encode(root.id), untilId: MisskeyCompat::MiId.encode(accepted.status_id) }, as: :json

    expect(response.parsed_body.pluck(:id)).to eq([MisskeyCompat::MiId.encode(reblog.id)])

    post '/api/notes/renotes', params: { i: read_token, noteId: MisskeyCompat::MiId.encode(root.id), sinceId: MisskeyCompat::MiId.encode(reblog.id) }, as: :json

    expect(response.parsed_body.pluck(:id)).to eq([MisskeyCompat::MiId.encode(accepted.status_id), MisskeyCompat::MiId.encode(newest.status_id)])
  end

  it 'deletes only the caller’s reblog and active quotes for the target note' do
    reblog = Fabricate(:status, account: account, reblog: root)
    accepted = Fabricate(:quote, quoted_status: root, status: Fabricate(:status, account: account, text: 'accepted'), state: :accepted)
    pending = Fabricate(:quote, quoted_status: root, status: Fabricate(:status, account: account, text: 'pending'), state: :pending)
    rejected = Fabricate(:quote, quoted_status: root, status: Fabricate(:status, account: account, text: 'rejected'), state: :rejected)
    other = Fabricate(:quote, quoted_status: root, status: Fabricate(:status, text: 'other'), state: :accepted)

    post '/api/notes/unrenote', params: { i: write_token, noteId: MisskeyCompat::MiId.encode(root.id) }, as: :json

    expect(response).to have_http_status(204), response.body
    expect(Status.where(id: [reblog.id, accepted.status_id, pending.status_id])).to be_empty
    expect(Status.where(id: [rejected.status_id, other.status_id]).count).to eq(2)
  end
end
