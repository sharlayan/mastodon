# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat notification endpoints' do
  let(:user)        { Fabricate(:user) }
  let(:account)     { user.account }
  let(:actor)       { Fabricate(:account) }
  let(:read_token)  { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read').token }
  let(:write_token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'write').token }

  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  describe 'POST /api/i/notifications' do
    it 'requires authentication and read scope' do
      post '/api/i/notifications', as: :json
      expect(response).to have_http_status(401)

      post '/api/i/notifications', params: { i: write_token }, as: :json
      expect(response).to have_http_status(403)
      expect(response.parsed_body.dig(:error, :code)).to eq('PERMISSION_DENIED')
    end

    it 'returns only supported notifications owned by the authenticated account' do
      follow = Fabricate(:follow, account: actor, target_account: account)
      notification = Fabricate(:notification, account: account, type: :follow, activity: follow)
      foreign_follow = Fabricate(:follow, account: account, target_account: actor)
      Fabricate(:notification, account: actor, type: :follow, activity: foreign_follow)
      Fabricate(:notification, account: account, type: :update, activity: Fabricate(:status, account: actor))

      post '/api/i/notifications', params: { i: read_token }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to contain_exactly(
        include(
          id: MisskeyCompat::MiId.encode(notification.id),
          type: 'follow',
          userId: MisskeyCompat::MiId.encode(actor.id),
          user: include(id: MisskeyCompat::MiId.encode(actor.id))
        )
      )
    end

    it 'filters before limiting and leaves the marker unchanged when markAsRead is false' do
      follow = Fabricate(:follow, account: actor, target_account: account)
      Fabricate(:notification, account: account, type: :follow, activity: follow)
      Fabricate(:notification, account: account, type: :status, activity: Fabricate(:status, account: actor))
      newer = Fabricate(:notification, account: account, type: :follow, activity: follow)

      post '/api/i/notifications', params: { i: read_token, includeTypes: ['follow'], excludeTypes: ['follow'], limit: 1, markAsRead: false }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to eq([MisskeyCompat::MiId.encode(newer.id)])
      expect(user.markers.find_by(timeline: 'notifications')).to be_nil

      post '/api/i/notifications', params: { i: read_token, excludeTypes: ['follow'], limit: 1, markAsRead: false }, as: :json

      expect(response.parsed_body.pluck(:type)).to eq(['note'])
      expect(user.markers.find_by(timeline: 'notifications')).to be_nil
    end

    it 'uses ten as the default limit and advances the marker even when filtering returns no notifications' do
      notifications = Array.new(11) do
        Fabricate(:notification, account: account, type: :status, activity: Fabricate(:status, account: actor))
      end

      post '/api/i/notifications', params: { i: read_token }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body.size).to eq(10)
      expect(response.parsed_body.first[:id]).to eq(MisskeyCompat::MiId.encode(notifications.last.id))

      post '/api/i/notifications', params: { i: read_token, includeTypes: ['follow'] }, as: :json

      expect(response.parsed_body).to eq([])
      expect(user.markers.find_by(timeline: 'notifications')&.last_read_id).to eq(notifications.last.id)
    end

    it 'returns since-only pages in ascending order and applies date boundaries' do
      notifications = [1, 2, 3, 4].map do |hour|
        Fabricate(:notification, account: account, type: :status, activity: Fabricate(:status, account: actor), created_at: Time.zone.local(2026, 1, 1, hour))
      end

      post '/api/i/notifications', params: { i: read_token, sinceId: MisskeyCompat::MiId.encode(notifications.first.id), limit: 2, markAsRead: false }, as: :json

      expect(response.parsed_body.pluck(:id)).to eq(notifications[1..2].map { |notification| MisskeyCompat::MiId.encode(notification.id) })

      post '/api/i/notifications', params: { i: read_token, sinceDate: Time.zone.local(2026, 1, 1, 2).to_i * 1000, untilDate: Time.zone.local(2026, 1, 1, 4).to_i * 1000, markAsRead: false }, as: :json

      expect(response.parsed_body.pluck(:id)).to eq([MisskeyCompat::MiId.encode(notifications[2].id)])
    end

    it 'finds matching notifications beyond a batch without loading excluded notes' do
      follow = Fabricate(:follow, account: actor, target_account: account)
      matching = Fabricate(:notification, account: account, type: :follow, activity: follow)
      Array.new(101) do
        Fabricate(:notification, account: account, type: :status, activity: Fabricate(:status, account: actor))
      end
      read_token

      queries = collect_queries do
        post '/api/i/notifications', params: { i: read_token, includeTypes: ['follow'], limit: 1, markAsRead: false }, as: :json
      end

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to eq([MisskeyCompat::MiId.encode(matching.id)])
      expect(queries.grep(/FROM "statuses"/)).to be_empty
    end

    it 'distinguishes replies from mentions before applying the page limit' do
      parent = Fabricate(:status, account: account)
      mention = Fabricate(:mention, account: account, status: Fabricate(:status, account: actor))
      reply = Fabricate(:mention, account: account, status: Fabricate(:status, account: actor, thread: parent))
      mention_notification = Fabricate(:notification, account: account, type: :mention, activity: mention)
      reply_notification = Fabricate(:notification, account: account, type: :mention, activity: reply)

      post '/api/i/notifications', params: { i: read_token, includeTypes: ['mention'], limit: 1, markAsRead: false }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to contain_exactly(include(id: MisskeyCompat::MiId.encode(mention_notification.id), type: 'mention'))

      post '/api/i/notifications', params: { i: read_token, excludeTypes: ['mention'], limit: 1, markAsRead: false }, as: :json

      expect(response.parsed_body).to contain_exactly(include(id: MisskeyCompat::MiId.encode(reply_notification.id), type: 'reply'))

      post '/api/i/notifications', params: { i: read_token, includeTypes: ['mention', 'reply'], markAsRead: false }, as: :json

      expect(response.parsed_body.pluck(:id)).to eq([reply_notification, mention_notification].map { |notification| MisskeyCompat::MiId.encode(notification.id) })
    end

    it 'batches note queries while preserving renotes and custom reactions' do
      statuses = Array.new(10) { Fabricate(:status, account: actor) }
      statuses.each { |status| Fabricate(:notification, account: account, type: :status, activity: status) }
      read_token

      post '/api/i/notifications', params: { i: read_token, limit: 1, markAsRead: false }, as: :json
      counts = [1, 10].map do |limit|
        queries = collect_queries do
          post '/api/i/notifications', params: { i: read_token, limit: limit, markAsRead: false }, as: :json
        end
        expect(response).to have_http_status(200)
        expect(response.parsed_body.size).to eq(limit)
        queries.grep(/FROM "(?:statuses|status_reactions|mentions|media_attachments)"/).size
      end
      expect(counts.last).to eq(counts.first)

      renote = Fabricate(:status, account: actor, reblog: statuses.first)
      Fabricate(:notification, account: account, type: :reblog, activity: renote)
      emoji = Fabricate(:custom_emoji)
      reaction = Fabricate(:status_reaction, account: actor, status: statuses.first, custom_emoji: emoji, name: emoji.shortcode)
      Fabricate(:notification, account: account, type: :reaction, activity: reaction)

      post '/api/i/notifications', params: { i: read_token, includeTypes: ['renote', 'reaction'], markAsRead: false }, as: :json

      expect(response.parsed_body).to contain_exactly(
        include(type: 'renote', note: include(id: MisskeyCompat::MiId.encode(renote.id), renoteId: MisskeyCompat::MiId.encode(statuses.first.id))),
        include(type: 'reaction', reaction: ":#{emoji.shortcode}@.:", note: include(id: MisskeyCompat::MiId.encode(statuses.first.id)))
      )
    end
  end

  describe 'POST /api/i/read-all-notifications' do
    it 'rejects a read-only token without advancing the marker' do
      follow = Fabricate(:follow, account: actor, target_account: account)
      Fabricate(:notification, account: account, type: :follow, activity: follow)

      post '/api/i/read-all-notifications', params: { i: read_token }, as: :json

      expect(response).to have_http_status(403)
      expect(user.markers.find_by(timeline: 'notifications')).to be_nil
    end

    it 'advances the notification marker to the latest owned notification' do
      follow = Fabricate(:follow, account: actor, target_account: account)
      latest = Fabricate(:notification, account: account, type: :follow, activity: follow)
      foreign_follow = Fabricate(:follow, account: account, target_account: actor)
      Fabricate(:notification, account: actor, type: :follow, activity: foreign_follow)

      post '/api/i/read-all-notifications', params: { i: write_token }, as: :json

      expect(response).to have_http_status(204)
      expect(user.markers.find_by(timeline: 'notifications')&.last_read_id).to eq(latest.id)
    end
  end

  def collect_queries(&block)
    queries = []
    callback = lambda do |*, payload|
      queries << payload[:sql] unless payload[:cached] || payload[:name].in?(%w(SCHEMA TRANSACTION))
    end
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &block)
    queries
  end
end
