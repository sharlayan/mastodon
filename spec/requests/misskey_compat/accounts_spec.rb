# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat account endpoints' do
  let(:user)        { Fabricate(:user) }
  let(:account)     { user.account }
  let(:target)      { Fabricate(:account) }
  let(:read_token)  { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read').token }
  let(:write_token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'write').token }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  it 'normalizes a negative directory offset and rejects offsets above the query budget' do
    target.update!(discoverable: true)
    target.account_stat.save!

    post '/api/users', params: { i: read_token, offset: -5 }, as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body.pluck('id')).to include(MisskeyCompat::MiId.encode(target.id))

    post '/api/users', params: { i: read_token, offset: 1_001 }, as: :json

    expect(response).to have_http_status(400)
    expect(response.parsed_body.dig('error', 'info', 'param')).to eq('#/properties/offset')
  end

  it 'rejects poll recommendation offsets above the query budget' do
    post '/api/notes/polls/recommendation', params: { i: read_token, offset: 1_001 }, as: :json

    expect(response).to have_http_status(400)
    expect(response.parsed_body.dig('error', 'code')).to eq('INVALID_PARAM')
  end

  it 'accepts a negative poll recommendation offset' do
    post '/api/notes/polls/recommendation', params: { i: read_token, offset: -1 }, as: :json

    expect(response).to have_http_status(200)
  end

  it 'keeps memo values null in directory and detailed search results' do
    target.update!(discoverable: true)
    target.account_stat.save!
    Fabricate(:account_note, account: account, target_account: target, comment: 'profile memo')

    post '/api/users', params: { i: read_token }, as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body.find { |item| item['id'] == MisskeyCompat::MiId.encode(target.id) }).to include('memo' => nil)

    post '/api/users/search-by-username-and-host', params: { i: read_token, username: target.username, detail: true }, as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body.find { |item| item['id'] == MisskeyCompat::MiId.encode(target.id) }).to include('memo' => nil)
  end

  it 'treats the Misskey local host marker as a local account filter' do
    post '/api/users/search-by-username-and-host', params: { i: read_token, username: target.username, host: '.' }, as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body.pluck('id')).to include(MisskeyCompat::MiId.encode(target.id))
  end

  it 'does not return remote accounts when filtering by the local host marker' do
    remote = Fabricate(:account, domain: 'remote.example', username: 'bob')
    local  = Fabricate(:account, username: 'bob')

    post '/api/users/search-by-username-and-host', params: { i: read_token, username: 'bob', host: '.' }, as: :json

    expect(response).to have_http_status(200)
    ids = response.parsed_body.pluck('id')
    expect(ids).to include(MisskeyCompat::MiId.encode(local.id))
    expect(ids).to_not include(MisskeyCompat::MiId.encode(remote.id))
  end

  it 'returns detailed users by default from the username search' do
    post '/api/users/search-by-username-and-host', params: { i: read_token, username: target.username, host: '.' }, as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body.find { |item| item['id'] == MisskeyCompat::MiId.encode(target.id) }).to include('url')
  end

  it 'returns lite users when detail is false' do
    post '/api/users/search-by-username-and-host', params: { i: read_token, username: target.username, host: '.', detail: false }, as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body.find { |item| item['id'] == MisskeyCompat::MiId.encode(target.id) }).to_not include('url')
  end

  it 'returns detailed users with viewer relationships by default from search' do
    target.update!(discoverable: true)
    account.follow!(target, reblogs: true, notify: false)

    post '/api/users/search', params: { i: read_token, query: target.username }, as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body.find { |item| item['id'] == MisskeyCompat::MiId.encode(target.id) }).to include('url', 'isFollowing' => true)
  end

  it 'returns lite users without viewer relationships when search detail is false' do
    target.update!(discoverable: true)

    post '/api/users/search', params: { i: read_token, query: target.username, detail: false }, as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body.find { |item| item['id'] == MisskeyCompat::MiId.encode(target.id) }).to_not include('url', 'isFollowing')
  end

  def create_mentioned_pointer_note(actor, index)
    mentioned = Fabricate(:account)
    status = Fabricate(:status, account: actor, text: "@#{mentioned.username} audit #{index}")
    Fabricate(:mention, status: status, account: mentioned)
    file = DriveFile.create!(account: actor, file: attachment_fixture('attachment.jpg'))
    file.build_pointer(actor).tap do |pointer|
      pointer.status = status
      pointer.save!
    end
  end

  def notes_collection_queries(actor)
    queries = []
    callback = lambda do |_name, _started, _finished, _unique_id, payload|
      queries << payload[:sql] if payload[:name] != 'SCHEMA' && !payload[:cached] && payload[:sql].match?(/\ASELECT/i)
    end

    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
      post '/api/users/notes', params: { i: read_token, userId: MisskeyCompat::MiId.encode(actor.id), limit: 10 }, as: :json
    end
    queries
  end

  describe 'POST /api/users/update-memo' do
    it 'requires authentication' do
      post '/api/users/update-memo', params: { userId: target.id, memo: 'private note' }, as: :json

      expect(response).to have_http_status(401)
      expect(response.parsed_body.dig(:error, :code)).to eq('CREDENTIAL_REQUIRED')
    end

    it 'rejects a read-only token without changing data' do
      post '/api/users/update-memo', params: { i: read_token, userId: target.id, memo: 'private note' }, as: :json

      expect(response).to have_http_status(403)
      expect(account.account_notes).to be_empty
    end

    it 'creates, updates, and clears a memo using a MiId userId' do
      encoded_id = MisskeyCompat::MiId.encode(target.id)

      post '/api/users/update-memo', params: { i: write_token, userId: encoded_id, memo: 'first' }, as: :json
      expect(response).to have_http_status(204)
      expect(account.account_notes.find_by(target_account: target)&.comment).to eq('first')

      post '/api/users/update-memo', params: { i: write_token, userId: encoded_id, memo: 'second' }, as: :json
      expect(response).to have_http_status(204)
      expect(account.account_notes.find_by(target_account: target)&.comment).to eq('second')

      post '/api/users/update-memo', params: { i: write_token, userId: encoded_id, memo: '' }, as: :json
      expect(response).to have_http_status(204)
      expect(account.account_notes.find_by(target_account: target)).to be_nil
    end

    it 'returns NO_SUCH_USER for an unknown account' do
      post '/api/users/update-memo', params: { i: write_token, userId: MisskeyCompat::MiId.encode(-1), memo: 'private note' }, as: :json

      expect(response).to have_http_status(404)
      expect(response.parsed_body.dig(:error, :code)).to eq('NO_SUCH_USER')
    end
  end

  describe 'POST /api/users/search' do
    it 'requires a read-capable token' do
      post '/api/users/search', params: { i: write_token, query: target.username }, as: :json

      expect(response).to have_http_status(403)
      expect(response.parsed_body.dig(:error, :code)).to eq('PERMISSION_DENIED')
    end

    it 'returns an empty result for a blank query' do
      post '/api/users/search', params: { i: read_token, query: '   ' }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to eq([])
    end
  end

  describe 'POST /api/users/notes' do
    it 'uses the Misskey withReplies parameter' do
      parent = Fabricate(:status)
      reply = Fabricate(:status, account: target, thread: parent)

      post '/api/users/notes', params: { i: read_token, userId: MisskeyCompat::MiId.encode(target.id), withReplies: true }, as: :json

      expect(response.parsed_body.pluck(:id)).to include(MisskeyCompat::MiId.encode(reply.id))
    end

    it 'rejects combining withReplies and withFiles' do
      post '/api/users/notes', params: { i: read_token, userId: MisskeyCompat::MiId.encode(target.id), withReplies: true, withFiles: true }, as: :json

      expect(response).to have_http_status(400)
      expect(response.parsed_body.dig(:error, :code)).to eq('INVALID_PARAM')
    end

    it 'preloads mentions and Drive pointer files for the note collection', :attachment_processing do
      actor = Fabricate(:account)
      Array.new(10) { |index| create_mentioned_pointer_note(actor, index) }
      queries = notes_collection_queries(actor)

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to be_an(Array)
      expect(response.parsed_body.size).to eq(10)
      expect(queries.count { |sql| sql.include?('FROM "mentions"') }).to eq(2)
      expect(queries.count { |sql| sql.include?('FROM "drive_files"') }).to eq(1)
      expect(queries.count { |sql| sql.include?('FROM "drive_file_names"') }).to eq(1)
    end
  end
end
