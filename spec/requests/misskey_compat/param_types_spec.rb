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

  def expect_invalid_param(param, label)
    expect(response).to have_http_status(400), label
    expect(response.parsed_body['error']).to include('code' => 'INVALID_PARAM'), label
    expect(response.parsed_body.dig('error', 'info', 'param')).to eq("#/properties/#{param}"), label
  end

  it 'rejects malformed limit, offset, cursor, date, and noteId values' do
    clip = Fabricate(:clip, account: account, public: true)
    status = Fabricate(:status, account: account)
    [
      ['/api/following/requests/list', { limit: true }, 'limit'],
      ['/api/hashtags/search', { query: 'foo', offset: [1] }, 'offset'],
      ['/api/blocking/list', { untilId: { a: 1 } }, 'untilId'],
      ['/api/mute/list', { sinceId: true }, 'sinceId'],
      ['/api/blocking/list', { untilDate: [1] }, 'untilDate'],
      ['/api/clips/add-note', { clipId: clip.id.to_s, noteId: [status.id.to_s] }, 'noteId'],
      ['/api/clips/notes', { clipId: clip.id.to_s, sinceId: 'abc' }, 'sinceId'],
      ['/api/blocking/list', { untilId: '99999999999999999999' }, 'untilId'],
    ].each do |path, params, param|
      post path, params: { i: token, **params }, as: :json

      expect_invalid_param(param, "#{path} #{params.inspect}")
    end
  end

  it 'keeps accepting numeric string, integer, and MiId pagination values' do
    block = account.block_relationships.create!(target_account: target)

    [{ untilId: (block.id + 1).to_s, limit: '10' }, { untilId: block.id + 1, limit: 10 }, { untilId: MisskeyCompat::MiId.encode(block.id + 1) }].each do |params|
      post '/api/blocking/list', params: { i: token, **params }, as: :json

      expect(response).to have_http_status(200), params.inspect
      expect(response.parsed_body.size).to eq(1), params.inspect
    end
  end
end
