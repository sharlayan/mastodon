# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat following collections' do
  let(:user)       { Fabricate(:user) }
  let(:account)    { user.account }
  let(:token)      { MisskeyCompat::MiAuth.issue_native_token(user).token }
  let(:read_token) { MisskeyCompat::MiAuth.issue_token(user, permission: 'read:following').token }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  it 'lists the caller follows as Following entities with notification filtering and pagination' do
    first = Fabricate(:follow, account: account, target_account: Fabricate(:account, username: 'first'))
    second = Fabricate(:follow, account: account, target_account: Fabricate(:account, username: 'second'), notify: true)
    Fabricate(:follow, target_account: account)

    post '/api/following/list', params: { i: read_token }, as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body.pluck(:id)).to eq([second, first].map { |follow| MisskeyCompat::MiId.encode(follow.id) })
    expect(response.parsed_body.first).to include(followeeId: MisskeyCompat::MiId.encode(second.target_account_id), followerId: MisskeyCompat::MiId.encode(account.id))
    expect(response.parsed_body.first[:followee]).to include(username: 'second', isFollowing: true)

    post '/api/following/list', params: { i: read_token, notification: true }, as: :json
    expect(response.parsed_body.pluck(:id)).to eq([MisskeyCompat::MiId.encode(second.id)])

    post '/api/following/list', params: { i: read_token, sinceId: MisskeyCompat::MiId.encode(first.id), limit: 1 }, as: :json
    expect(response.parsed_body.pluck(:id)).to eq([MisskeyCompat::MiId.encode(second.id)])
  end

  it 'lists outgoing follow requests with both parties' do
    target = Fabricate(:account, username: 'locked', locked: true)
    request = Fabricate(:follow_request, account: account, target_account: target)
    Fabricate(:follow_request, target_account: account)

    post '/api/following/requests/sent', params: { i: read_token }, as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body.size).to eq(1)
    expect(response.parsed_body.first).to include(id: MisskeyCompat::MiId.encode(request.id))
    expect(response.parsed_body.first[:follower]).to include(id: MisskeyCompat::MiId.encode(account.id))
    expect(response.parsed_body.first[:followee]).to include(username: 'locked')
  end

  it 'updates notification settings of every follow, validates notify and requires write permission' do
    follows = Array.new(2) { Fabricate(:follow, account: account) }
    other = Fabricate(:follow, notify: false)

    post '/api/following/update-all', params: { i: token, notify: 'normal', withReplies: true }, as: :json
    expect(response).to have_http_status(204)
    expect(follows.map { |follow| follow.reload.notify }).to all(be(true))
    expect(other.reload.notify).to be(false)

    post '/api/following/update-all', params: { i: token, notify: 'none' }, as: :json
    expect(follows.map { |follow| follow.reload.notify }).to all(be(false))

    post '/api/following/update-all', params: { i: token, notify: 'loud' }, as: :json
    expect(response).to have_http_status(400)

    post '/api/following/update-all', params: { i: read_token, notify: 'normal' }, as: :json
    expect(response).to have_http_status(403)
  end
end
