# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat public user lists' do
  let(:owner) { Fabricate(:user) }
  let(:viewer) { Fabricate(:user) }
  let(:owner_token) { Fabricate(:accessible_access_token, resource_owner_id: owner.id, scopes: 'read write').token }
  let(:viewer_token) { Fabricate(:accessible_access_token, resource_owner_id: viewer.id, scopes: 'read write').token }
  let(:followed) { Fabricate(:account) }
  let(:unfollowed) { Fabricate(:account) }
  let(:list) { Fabricate(:list, account: owner.account, title: 'Friends') }
  let(:list_id) { MisskeyCompat::MiId.encode(list.id) }

  before do
    Setting.misskey_compat_enabled = true
    [followed, unfollowed].each do |member|
      owner.account.follow!(member)
      list.accounts << member
    end
  end

  after { Setting.misskey_compat_enabled = false }

  it 'publishes a list through update and exposes it to other users while keeping private lists hidden' do
    post '/api/users/lists/show', params: { i: viewer_token, listId: list_id, forPublic: true }, as: :json
    expect(response).to have_http_status(404)

    post '/api/users/lists/update', params: { i: owner_token, listId: list_id, isPublic: 'yes' }, as: :json
    expect(response).to have_http_status(400)
    post '/api/users/lists/update', params: { i: owner_token, listId: list_id, isPublic: true }, as: :json
    expect(response.parsed_body).to include(isPublic: true, name: 'Friends')

    post '/api/users/lists/list', params: { userId: MisskeyCompat::MiId.encode(owner.account.id) }, as: :json
    expect(response.parsed_body).to contain_exactly(include(id: list_id, isPublic: true, userIds: contain_exactly(MisskeyCompat::MiId.encode(followed.id), MisskeyCompat::MiId.encode(unfollowed.id))))

    post '/api/users/lists/get-memberships', params: { listId: list_id, forPublic: true }, as: :json
    expect(response.parsed_body.pluck(:userId)).to contain_exactly(MisskeyCompat::MiId.encode(followed.id), MisskeyCompat::MiId.encode(unfollowed.id))

    post '/api/users/lists/show', params: { i: viewer_token, listId: list_id }, as: :json
    expect(response).to have_http_status(404)

    get "/api/v1/lists/#{list.id}", headers: { 'Authorization' => "Bearer #{viewer_token}" }
    expect(response).to have_http_status(404)

    post '/api/users/lists/update', params: { i: owner_token, listId: list_id, isPublic: false }, as: :json
    post '/api/users/lists/list', params: { userId: MisskeyCompat::MiId.encode(owner.account.id) }, as: :json
    expect(response.parsed_body).to eq([])
  end

  it 'favorites public lists once and reports likes on public show' do
    MisskeyUserListSetting.update_public!(list, true)

    post '/api/users/lists/favorite', params: { i: viewer_token, listId: list_id }, as: :json
    expect(response).to have_http_status(204)
    post '/api/users/lists/favorite', params: { i: viewer_token, listId: list_id }, as: :json
    expect(response.parsed_body[:error]).to include(code: 'ALREADY_FAVORITED', id: '6425bba0-985b-461e-af1b-518070e72081')

    post '/api/users/lists/show', params: { i: viewer_token, listId: list_id, forPublic: true }, as: :json
    expect(response.parsed_body).to include(likedCount: 1, isLiked: true)
    post '/api/users/lists/show', params: { listId: list_id }, as: :json
    expect(response.parsed_body).to include(likedCount: 1, isLiked: false)

    post '/api/users/lists/unfavorite', params: { i: viewer_token, listId: list_id }, as: :json
    expect(response).to have_http_status(204)
    post '/api/users/lists/unfavorite', params: { i: viewer_token, listId: list_id }, as: :json
    expect(response.parsed_body[:error]).to include(id: '835c4b27-463d-4cfa-969b-a9058678d465')
  end

  it 'copies a public list with only the members the viewer may add and refuses when a member blocks the viewer' do
    MisskeyUserListSetting.update_public!(list, true)
    viewer.account.follow!(followed)
    post '/api/users/lists/create-from-public', params: { i: viewer_token, listId: list_id, name: 'Copied' }, as: :json
    expect(response).to have_http_status(200)
    copy = viewer.account.owned_lists.find(MisskeyCompat::MiId.decode(response.parsed_body[:id]))
    expect(response.parsed_body).to include(name: 'Copied', isPublic: false, userIds: [MisskeyCompat::MiId.encode(followed.id)])
    expect(copy.accounts).to eq([followed])

    unfollowed.block!(viewer.account)
    post '/api/users/lists/create-from-public', params: { i: viewer_token, listId: list_id, name: 'Blocked' }, as: :json
    expect(response.parsed_body.dig(:error, :code)).to eq('YOU_HAVE_BEEN_BLOCKED')
    expect(viewer.account.owned_lists.count).to eq(1)
  end

  it 'rejects favorites and copies of private or missing lists with the Misskey error ids' do
    post '/api/users/lists/favorite', params: { i: viewer_token, listId: list_id }, as: :json
    expect(response.parsed_body[:error]).to include(code: 'NO_SUCH_USER_LIST', id: '7dbaf3cf-7b42-4b8f-b431-b3919e580dbe')

    post '/api/users/lists/create-from-public', params: { i: viewer_token, listId: list_id, name: 'Copy' }, as: :json
    expect(response.parsed_body[:error]).to include(code: 'NO_SUCH_LIST', id: '9292f798-6175-4f7d-93f4-b6742279667d')

    post '/api/users/lists/create-from-public', params: { i: viewer_token, listId: list_id, name: '' }, as: :json
    expect(response).to have_http_status(400)

    post '/api/users/lists/list', as: :json
    expect(response.parsed_body.dig(:error, :id)).to eq('ab36de0e-29e9-48cb-9732-d82f1281620d')
    post '/api/users/lists/list', params: { userId: MisskeyCompat::MiId.encode(Fabricate(:account, domain: 'remote.example').id) }, as: :json
    expect(response.parsed_body.dig(:error, :code)).to eq('REMOTE_USER_NOT_ALLOWED')
  end
end
