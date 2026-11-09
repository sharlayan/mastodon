# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat parameter types' do
  let(:user)    { Fabricate(:user) }
  let(:account) { user.account }
  let(:target)  { Fabricate(:account) }
  let(:token)   { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write').token }

  before do
    Setting.misskey_compat_enabled = true
    Setting.clips_enabled = true
  end

  after do
    Setting.misskey_compat_enabled = false
    Setting.clips_enabled = false
  end

  def expect_invalid_param(param)
    expect(response).to have_http_status(400)
    expect(response.parsed_body['error']).to include('code' => 'INVALID_PARAM')
    expect(response.parsed_body.dig('error', 'info', 'param')).to eq("#/properties/#{param}")
  end

  it 'rejects a boolean limit' do
    post '/api/following/requests/list', params: { i: token, limit: true }, as: :json

    expect_invalid_param('limit')
  end

  it 'rejects an array offset' do
    post '/api/hashtags/search', params: { i: token, query: 'foo', offset: [1] }, as: :json

    expect_invalid_param('offset')
  end

  it 'rejects an object untilId' do
    post '/api/blocking/list', params: { i: token, untilId: { a: 1 } }, as: :json

    expect_invalid_param('untilId')
  end

  it 'rejects a boolean sinceId' do
    post '/api/mute/list', params: { i: token, sinceId: true }, as: :json

    expect_invalid_param('sinceId')
  end

  it 'rejects an array untilDate' do
    post '/api/blocking/list', params: { i: token, untilDate: [1] }, as: :json

    expect_invalid_param('untilDate')
  end

  it 'rejects an array noteId' do
    clip = Fabricate(:clip, account: account)
    status = Fabricate(:status, account: account)

    post '/api/clips/add-note', params: { i: token, clipId: clip.id.to_s, noteId: [status.id.to_s] }, as: :json

    expect_invalid_param('noteId')
  end

  it 'rejects a non-numeric sinceId for clip notes instead of failing in the database' do
    clip = Fabricate(:clip, account: account, public: true)

    post '/api/clips/notes', params: { i: token, clipId: clip.id.to_s, sinceId: 'abc' }, as: :json

    expect_invalid_param('sinceId')
  end

  it 'rejects an out of range untilId' do
    post '/api/blocking/list', params: { i: token, untilId: '99999999999999999999' }, as: :json

    expect_invalid_param('untilId')
  end

  it 'keeps accepting numeric string and integer pagination values' do
    block = account.block_relationships.create!(target_account: target)

    post '/api/blocking/list', params: { i: token, untilId: (block.id + 1).to_s, limit: '10' }, as: :json
    expect(response).to have_http_status(200)
    expect(response.parsed_body.size).to eq(1)

    post '/api/blocking/list', params: { i: token, untilId: block.id + 1, limit: 10 }, as: :json
    expect(response).to have_http_status(200)
    expect(response.parsed_body.size).to eq(1)
  end

  it 'keeps accepting MiId pagination values' do
    block = account.block_relationships.create!(target_account: target)

    post '/api/blocking/list', params: { i: token, untilId: MisskeyCompat::MiId.encode(block.id + 1) }, as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body.size).to eq(1)
  end
end
