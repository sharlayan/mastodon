# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat clips' do
  let(:user)        { Fabricate(:user) }
  let(:read_token)  { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read').token }
  let(:write_token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'write').token }

  before do
    Setting.misskey_compat_enabled = true
    Setting.clips_enabled = true
  end

  after do
    Setting.misskey_compat_enabled = false
    Setting.clips_enabled = false
  end

  describe 'POST /api/notes/clips' do
    let(:status) { Fabricate(:status) }

    it 'returns a bounded page and accepts the last clip ID as a cursor' do
      clips = Fabricate.times(21, :clip, public: true)
      clips.each { |clip| clip.clip_statuses.create!(status: status) }

      post '/api/notes/clips', params: { noteId: MisskeyCompat::MiId.encode(status.id) }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body.size).to eq(20)

      cursor = response.parsed_body.last[:id]
      post '/api/notes/clips', params: { noteId: MisskeyCompat::MiId.encode(status.id), untilId: cursor }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to contain_exactly(MisskeyCompat::MiId.encode(clips.first.id))
    end

    it 'preloads accounts and clip relationships for the collection' do
      clips = Fabricate.times(3, :clip, public: true)
      clips.each do |clip|
        clip.clip_statuses.create!(status: status)
        ClipFavourite.create!(clip: clip, account: Fabricate(:account))
      end

      queries = []
      callback = lambda do |_name, _started, _finished, _unique_id, payload|
        queries << payload[:sql] if payload[:name] != 'SCHEMA' && !payload[:cached]
      end

      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
        post '/api/notes/clips', params: { i: read_token, noteId: MisskeyCompat::MiId.encode(status.id) }, as: :json
      end

      expect(response).to have_http_status(200)
      expect(queries.count { |sql| sql.include?('FROM "accounts"') && sql.include?('WHERE "accounts"."id" IN') }).to eq(1)
      expect(queries.count { |sql| sql.include?('FROM "clip_favourites"') }).to eq(2)
      expect(response.parsed_body.pluck(:favoritedCount)).to all(eq(1))
      expect(response.parsed_body.pluck(:isFavorited)).to all(be(false))
    end
  end

  describe 'POST /api/clips/create' do
    it 'locks the account while validating the per-account limit' do
      queries = []
      callback = lambda do |_name, _started, _finished, _unique_id, payload|
        queries << payload[:sql] if payload[:name] != 'SCHEMA' && !payload[:cached]
      end

      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
        post '/api/clips/create', params: { i: write_token, name: 'bounded clip' }, as: :json
      end

      expect(response).to have_http_status(200)
      expect(queries.any? { |sql| sql.include?('FROM "accounts"') && sql.include?('FOR UPDATE') }).to be(true)
    end
  end

  describe 'POST /api/clips/notes' do
    let(:clip) { Fabricate(:clip, public: true) }
    let!(:statuses) { Fabricate.times(21, :status) }

    before do
      statuses.each { |status| clip.clip_statuses.create!(status: status) }
    end

    it 'returns a bounded page and accepts the last note ID as a cursor' do
      post '/api/clips/notes', params: { clipId: MisskeyCompat::MiId.encode(clip.id) }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body.size).to eq(20)

      cursor = response.parsed_body.last[:id]
      post '/api/clips/notes', params: { clipId: MisskeyCompat::MiId.encode(clip.id), untilId: cursor }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to contain_exactly(MisskeyCompat::MiId.encode(statuses.first.id))
    end

    it 'filters notes that are not visible to an anonymous reader' do
      hidden_status = statuses.last
      hidden_status.update!(visibility: :direct)

      post '/api/clips/notes', params: { clipId: MisskeyCompat::MiId.encode(clip.id) }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to_not include(MisskeyCompat::MiId.encode(hidden_status.id))
    end

    it 'hides clips owned by an account that has requested deletion' do
      clip.account.mark_deleted!

      post '/api/clips/notes', params: { clipId: MisskeyCompat::MiId.encode(clip.id) }, as: :json

      expect(response).to have_http_status(404)
      expect(response.parsed_body.dig(:error, :code)).to eq('NO_SUCH_CLIP')
    end

    it 'rate limits authenticated callers as potential attackers' do
      limiter = RateLimiter.new(user.account, family: :clip_notes)
      RateLimiter::FAMILIES[:clip_notes][:limit].times { limiter.record! }

      post '/api/clips/notes', params: { i: write_token, clipId: MisskeyCompat::MiId.encode(clip.id) }, as: :json

      expect(response).to have_http_status(429)
      expect(response.parsed_body.dig(:error, :code)).to eq('RATE_LIMIT_EXCEEDED')
      expect(response.headers['Cache-Control']).to eq('private, no-store')
      expect(response.headers['Retry-After'].to_i).to be_positive
    end
  end

  describe 'POST /api/clips/add-note' do
    let(:clip) { Fabricate(:clip, account: user.account, public: false) }

    before { stub_const('Clip::STATUSES_LIMIT', 1) }

    it 'rejects a different note once the clip is full' do
      clip.clip_statuses.create!(status: Fabricate(:status))

      expect do
        post '/api/clips/add-note',
             params: { i: write_token, clipId: MisskeyCompat::MiId.encode(clip.id), noteId: MisskeyCompat::MiId.encode(Fabricate(:status).id) },
             as: :json
      end.to_not change(ClipStatus, :count)

      expect(response).to have_http_status(400)
      expect(response.parsed_body.dig(:error, :code)).to eq('INVALID_PARAM')
    end
  end
end
