# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat error envelope' do
  let(:user)    { Fabricate(:user) }
  let(:account) { user.account }
  let(:target)  { Fabricate(:account) }
  let(:token)   { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write').token }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  def error_body
    response.parsed_body['error']
  end

  it 'renders malformed JSON bodies as an INVALID_PARAM error' do
    post '/api/following/create', params: '{', headers: { 'CONTENT_TYPE' => 'application/json', 'Authorization' => "Bearer #{token}" }

    expect(response).to have_http_status(400)
    expect(response.media_type).to eq('application/json')
    expect(error_body).to include('code' => 'INVALID_PARAM')
  end

  it 'renders policy denials as an ACCESS_DENIED error' do
    poll = Fabricate(:poll, account: target, options: %w(a b))
    status = Fabricate(:status, account: target, poll: poll)
    account.block!(target)

    post '/api/notes/polls/vote', params: { i: token, noteId: status.id.to_s, choice: 0 }, as: :json

    expect(response).to have_http_status(403)
    expect(response.media_type).to eq('application/json')
    expect(error_body).to include('code' => 'ACCESS_DENIED', 'id' => '56f35758-7dd5-468b-8439-5d6fb8ec9b8e')
  end

  it 'renders unfollowable targets as an ACCESS_DENIED error and following yourself as FOLLOWEE_IS_YOURSELF' do
    target.update!(moved_to_account: Fabricate(:account))

    post '/api/following/create', params: { i: token, userId: target.id.to_s }, as: :json

    expect(response).to have_http_status(403)
    expect(error_body).to include('code' => 'ACCESS_DENIED')

    post '/api/following/create', params: { i: token, userId: account.id.to_s }, as: :json

    expect(response).to have_http_status(400)
    expect(error_body).to include('code' => 'FOLLOWEE_IS_YOURSELF', 'id' => '26fbe7bb-a331-4857-af17-205b426669a9')
  end

  it 'reports a blocker with the Misskey BLOCKED error' do
    target.block!(account)

    post '/api/following/create', params: { i: token, userId: target.id.to_s }, as: :json

    expect(response).to have_http_status(400)
    expect(error_body).to include('code' => 'BLOCKED', 'id' => 'c4ab57cc-4e41-45e9-bfd9-584f61e35ce0')
  end

  it 'reports a blocked target with the Misskey BLOCKING error' do
    account.block!(target)

    post '/api/following/create', params: { i: token, userId: target.id.to_s }, as: :json

    expect(response).to have_http_status(400)
    expect(error_body).to include('code' => 'BLOCKING', 'id' => '4e2206ec-aa4f-4960-b865-6c23ac38e2d9')
  end

  it 'reports accepting a missing follow request with NO_FOLLOW_REQUEST, treats rejecting one as a no-op, and still rejects pending requests' do
    post '/api/following/requests/accept', params: { i: token, userId: target.id.to_s }, as: :json

    expect(response).to have_http_status(400)
    expect(error_body).to include('code' => 'NO_FOLLOW_REQUEST', 'id' => 'bcde4f8b-0913-4614-8881-614e522fb041')

    post '/api/following/requests/reject', params: { i: token, userId: target.id.to_s }, as: :json

    expect(response).to have_http_status(204)

    Fabricate(:follow_request, account: target, target_account: account)
    post '/api/following/requests/reject', params: { i: token, userId: target.id.to_s }, as: :json

    expect(response).to have_http_status(204)
    expect(FollowRequest.where(account: target, target_account: account)).to be_empty
  end
end
