# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat users/lists/list endpoint' do
  let(:user) { Fabricate(:user) }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read').token }

  before { Setting.misskey_compat_enabled = true }
  after { Setting.misskey_compat_enabled = false }

  it 'returns list members and leaves memberships unchanged' do
    list = Fabricate(:list, account: user.account)
    member = Fabricate(:account)
    Fabricate(:follow, account: user.account, target_account: member)
    membership = list.list_accounts.create!(account: member, with_replies: true)

    post '/api/users/lists/list', params: { i: token }, as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body).to include(include('id' => MisskeyCompat::MiId.encode(list.id), 'userIds' => [MisskeyCompat::MiId.encode(member.id)]))

    post '/api/users/lists/get-memberships', params: { i: token, listId: MisskeyCompat::MiId.encode(list.id) }, as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body).to contain_exactly(include('id' => MisskeyCompat::MiId.encode(membership.id), 'userId' => MisskeyCompat::MiId.encode(member.id), 'withReplies' => true))
  end

  it 'reports when each member was added instead of the Unix epoch' do
    list = Fabricate(:list, account: user.account, created_at: 3.days.ago)
    followed = Fabricate(:account)
    follow = Fabricate(:follow, account: user.account, target_account: followed, created_at: 2.days.ago)
    list.list_accounts.create!(account: followed)
    list.list_accounts.create!(account: user.account)

    post '/api/users/lists/get-memberships', params: { i: token, listId: MisskeyCompat::MiId.encode(list.id) }, as: :json

    expect(response).to have_http_status(200)
    created_at = response.parsed_body.to_h { |membership| [membership['userId'], membership['createdAt']] }
    expect(created_at).to eq(
      MisskeyCompat::MiId.encode(followed.id) => follow.created_at.utc.iso8601,
      MisskeyCompat::MiId.encode(user.account.id) => list.created_at.utc.iso8601
    )
  end
end
