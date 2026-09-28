# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat HTTP timeline contract' do
  let(:user) { Fabricate(:user) }
  let(:account) { user.account }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read').token }

  before do
    Setting.misskey_compat_enabled = true
    Setting.local_live_feed_access = 'public'
    Setting.remote_live_feed_access = 'public'
  end

  after { Setting.misskey_compat_enabled = false }

  it 'combines followed remote notes and local public notes without unrelated remote notes in hybrid' do
    followed = Fabricate(:account, domain: 'followed.example')
    unrelated = Fabricate(:account, domain: 'unrelated.example')
    Fabricate(:follow, account: account, target_account: followed)
    followed_private = Fabricate(:status, account: followed, visibility: :private)
    local_public = Fabricate(:status, account: Fabricate(:account))
    unrelated_public = Fabricate(:status, account: unrelated)

    post '/api/notes/hybrid-timeline', params: { i: token }, as: :json

    ids = response.parsed_body.pluck(:id)
    expect(ids).to include(MisskeyCompat::MiId.encode(followed_private.id), MisskeyCompat::MiId.encode(local_public.id))
    expect(ids).to_not include(MisskeyCompat::MiId.encode(unrelated_public.id))
  end

  it 'hides replies to others by default and accepts withReplies on local and hybrid' do
    other = Fabricate(:account)
    parent = Fabricate(:status, account: other)
    reply = Fabricate(:status, account: account, in_reply_to_id: parent.id, in_reply_to_account_id: other.id)
    self_parent = Fabricate(:status, account: account)
    self_reply = Fabricate(:status, account: account, in_reply_to_id: self_parent.id, in_reply_to_account_id: account.id)

    %w(local-timeline hybrid-timeline).each do |timeline|
      path = "/api/notes/#{timeline}"
      post path, params: { i: token }, as: :json
      expect(response.parsed_body.pluck(:id)).to include(MisskeyCompat::MiId.encode(self_reply.id))
      expect(response.parsed_body.pluck(:id)).to_not include(MisskeyCompat::MiId.encode(reply.id))

      post path, params: { i: token, withReplies: true }, as: :json
      expect(response.parsed_body.pluck(:id)).to include(MisskeyCompat::MiId.encode(reply.id))

      post path, params: { i: token, withReplies: true, withFiles: true }, as: :json
      expect(response).to have_http_status(400)
      expect(response.parsed_body.dig(:error, :code)).to eq('BOTH_WITH_REPLIES_AND_WITH_FILES')
    end
  end

  it 'uses a default limit of ten and fills filtered file pages across all four timelines' do
    first = Fabricate(:status, account: account)
    second = Fabricate(:status, account: account)
    Fabricate(:media_attachment, account: account, status: first)
    Fabricate(:media_attachment, account: account, status: second)
    Array.new(12) { Fabricate(:status, account: account) }

    %w(timeline local-timeline hybrid-timeline global-timeline).each do |timeline|
      path = "/api/notes/#{timeline}"
      post path, params: { i: token }, as: :json
      expect(response.parsed_body.size).to eq(10)

      post path, params: { i: token, withFiles: true, limit: 2 }, as: :json
      expect(response.parsed_body.pluck(:id)).to contain_exactly(MisskeyCompat::MiId.encode(first.id), MisskeyCompat::MiId.encode(second.id))
    end
  end

  it 'excludes pure renotes without removing ordinary notes' do
    original = Fabricate(:status, account: Fabricate(:account))
    normal = Fabricate(:status, account: account)
    renote = Fabricate(:status, account: account, reblog: original, text: '')

    %w(timeline local-timeline hybrid-timeline global-timeline).each do |timeline|
      post "/api/notes/#{timeline}", params: { i: token, withRenotes: false }, as: :json

      expect(response.parsed_body.pluck(:id)).to include(MisskeyCompat::MiId.encode(normal.id))
      expect(response.parsed_body.pluck(:id)).to_not include(MisskeyCompat::MiId.encode(renote.id))
    end
  end
end
