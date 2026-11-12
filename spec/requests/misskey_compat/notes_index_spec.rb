# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat global note listing' do
  let(:user)    { Fabricate(:user) }
  let(:account) { user.account }
  let(:token)   { MisskeyCompat::MiAuth.issue_token(user, permission: 'read:account').token }

  before do
    Setting.misskey_compat_enabled = true
    Setting.local_live_feed_access = 'public'
    Setting.remote_live_feed_access = 'public'
  end

  after { Setting.misskey_compat_enabled = false }

  def note_ids(**params)
    post '/api/notes', params: params, as: :json
    expect(response).to have_http_status(200)
    response.parsed_body.pluck(:id)
  end

  def encoded(*statuses)
    statuses.map { |status| MisskeyCompat::MiId.encode(status.id) }
  end

  it 'lists public federated notes newest first and applies every Misskey filter' do
    author = Fabricate(:account)
    remote = Fabricate(:status, account: Fabricate(:account, domain: 'remote.example'))
    plain = Fabricate(:status, account: author)
    reply = Fabricate(:status, account: author, thread: plain)
    renote = Fabricate(:status, account: author, reblog: plain)
    with_poll = Fabricate(:status, account: author, poll: Fabricate.build(:poll, account: author))
    with_file = Fabricate(:status, account: author)
    Fabricate(:media_attachment, account: author, status: with_file)
    Fabricate(:status, account: author, visibility: :unlisted)
    Fabricate(:status, account: author, local_only: true)

    expect(note_ids).to eq(encoded(with_file, with_poll, renote, reply, plain, remote))
    expect(note_ids(local: true)).to_not include(*encoded(remote))
    expect(note_ids(reply: true)).to eq(encoded(reply))
    expect(note_ids(renote: true)).to eq(encoded(renote))
    expect(note_ids(renote: false, reply: false, poll: false, withFiles: false)).to eq(encoded(plain, remote))
    expect(note_ids(poll: true)).to eq(encoded(with_poll))
    expect(note_ids(withFiles: true)).to eq(encoded(with_file))
    expect(note_ids(sinceId: encoded(renote).first, limit: 1)).to eq(encoded(with_poll))
  end

  it 'hides blocked accounts from a signed-in viewer and follows the public feed access settings' do
    blocked = Fabricate(:account)
    note = Fabricate(:status, account: blocked)
    Fabricate(:block, account: account, target_account: blocked)

    expect(note_ids).to eq(encoded(note))
    expect(note_ids(i: token)).to be_empty

    Setting.local_live_feed_access = 'authenticated'
    Setting.remote_live_feed_access = 'authenticated'
    expect(note_ids).to be_empty
  end
end
