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
    it 'omits notes after the recipient loses access to them' do
      account.follow!(actor)
      status = Fabricate(:status, account: actor, visibility: :private)
      notification = Fabricate(:notification, account: account, type: :status, activity: status)

      post '/api/i/notifications', params: { i: read_token, markAsRead: false }, as: :json
      expect(response.parsed_body).to contain_exactly(include(id: MisskeyCompat::MiId.encode(notification.id), note: include(text: status.text)))

      account.unfollow!(actor)

      post '/api/i/notifications', params: { i: read_token, markAsRead: false }, as: :json
      expect(response).to have_http_status(200)
      expect(response.parsed_body).to eq([])
    end

    it 'requires authentication and read scope' do
      post '/api/i/notifications', as: :json
      expect(response).to have_http_status(401)

      post '/api/i/notifications', params: { i: write_token }, as: :json
      expect(response).to have_http_status(403)
      expect(response.parsed_body.dig(:error, :code)).to eq('PERMISSION_DENIED')
    end

    it 'returns only supported notifications owned by the authenticated account and not held back by the notification policy' do
      follow = Fabricate(:follow, account: actor, target_account: account)
      notification = Fabricate(:notification, account: account, type: :follow, activity: follow)
      Fabricate(:notification, account: account, type: :follow, activity: Fabricate(:follow, account: Fabricate(:account), target_account: account), filtered: true)
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

  describe 'Misskey-only notifications' do
    let(:compat_app) { Fabricate(:application, name: 'Compat App') }
    let(:app_token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, application: compat_app, scopes: 'read write').token }

    it 'validates and creates app and test notifications with the token application as the default header' do
      post '/api/notifications/create', params: { i: read_token, body: 'denied' }, as: :json
      expect(response).to have_http_status(403)

      post '/api/notifications/create', params: { i: app_token }, as: :json
      expect(response).to have_http_status(400)

      post '/api/notifications/create', params: { i: app_token, body: 'Build finished' }, as: :json
      expect(response).to have_http_status(204)
      post '/api/notifications/create', params: { i: app_token, body: 'Custom', header: 'Header', icon: 'https://example.com/icon.png' }, as: :json
      post '/api/notifications/test-notification', params: { i: app_token }, as: :json
      expect(response).to have_http_status(204)

      post '/api/i/notifications', params: { i: read_token, markAsRead: false }, as: :json

      test_notification = MisskeyNotification.find_by(notification_type: 'test')
      expect(response.parsed_body).to match([
                                              eq('id' => MisskeyCompat::MiId.encode(test_notification.id), 'createdAt' => test_notification.created_at.iso8601, 'type' => 'test'),
                                              include(type: 'app', body: 'Custom', header: 'Header', icon: 'https://example.com/icon.png'),
                                              include(type: 'app', body: 'Build finished', header: 'Compat App', icon: nil).and(satisfy { |item| !item.key?('userId') }),
                                            ])
    end

    it 'merges Misskey-only notifications into Mastodon pages by id, type filters and the read marker' do
      older = Fabricate(:notification, account: account, type: :follow, activity: Fabricate(:follow, account: actor, target_account: account))
      app_notification = MisskeyCompat::Notifier.notify!(account, 'app', body: 'one', header: nil, icon: nil)
      test_notification = MisskeyCompat::Notifier.notify!(account, 'test')
      newer = Fabricate(:notification, account: account, type: :status, activity: Fabricate(:status, account: actor))

      post '/api/i/notifications', params: { i: read_token, markAsRead: false }, as: :json
      expect(response.parsed_body.pluck(:id)).to eq([newer, test_notification, app_notification, older].map { |n| MisskeyCompat::MiId.encode(n.id) })

      post '/api/i/notifications', params: { i: read_token, untilId: MisskeyCompat::MiId.encode(test_notification.id), limit: 1, markAsRead: false }, as: :json
      expect(response.parsed_body.pluck(:id)).to eq([MisskeyCompat::MiId.encode(app_notification.id)])

      post '/api/i/notifications', params: { i: read_token, excludeTypes: ['app', 'test'], markAsRead: false }, as: :json
      expect(response.parsed_body.pluck(:type)).to eq(%w(note follow))

      newest = MisskeyCompat::Notifier.notify!(account, 'test')
      post '/api/i/notifications', params: { i: read_token, includeTypes: ['test'] }, as: :json
      expect(response.parsed_body.pluck(:id)).to eq([newest, test_notification].map { |n| MisskeyCompat::MiId.encode(n.id) })
      expect(user.markers.find_by(timeline: 'notifications').last_read_id).to eq(newest.id)
    end

    it 'publishes Misskey-only notifications to the main stream, keeps only the newest per account and skips muted notifiers' do
      stub_const('MisskeyNotification::PER_ACCOUNT_LIMIT', 2)
      allow(redis).to receive(:exists?).and_call_original
      allow(redis).to receive(:exists?).with("subscribed:misskey:main:#{account.id}").and_return(true)
      allow(redis).to receive(:publish)
      remote = Fabricate(:account, domain: 'remote.example')

      first = MisskeyCompat::Notifier.notify!(account, 'achievementEarned', achievement: 'notes1')
      MisskeyCompat::Notifier.notify!(account, 'test')
      third = MisskeyCompat::Notifier.notify!(account, 'test')
      account.mute!(actor)

      expect(MisskeyCompat::Notifier.notify!(account, 'test', from_account: actor)).to be_nil
      expect(MisskeyCompat::Notifier.notify!(remote, 'test')).to be_nil
      expect(MisskeyNotification.where(account: account).order(:id).pluck(:id)).to eq([third.id - 1, third.id])
      expect(redis).to have_received(:publish).with("misskey:main:#{account.id}", JSON.generate({ event: 'main', payload: { type: 'notification', body: { id: MisskeyCompat::MiId.encode(first.id), createdAt: first.created_at.iso8601, type: 'achievementEarned', achievement: 'notes1' } } }))
      expect(redis).to have_received(:publish).exactly(3).times
    end
  end

  describe 'POST /api/i/read-all-notifications' do
    it 'rejects a read-only token without advancing the marker, then advances it to the latest owned notification' do
      follow = Fabricate(:follow, account: actor, target_account: account)
      latest = Fabricate(:notification, account: account, type: :follow, activity: follow)
      foreign_follow = Fabricate(:follow, account: account, target_account: actor)
      Fabricate(:notification, account: actor, type: :follow, activity: foreign_follow)

      post '/api/i/read-all-notifications', params: { i: read_token }, as: :json

      expect(response).to have_http_status(403)
      expect(user.markers.find_by(timeline: 'notifications')).to be_nil

      post '/api/i/read-all-notifications', params: { i: write_token }, as: :json

      expect(response).to have_http_status(204)
      expect(user.markers.find_by(timeline: 'notifications')&.last_read_id).to eq(latest.id)
    end
  end

  describe 'POST /api/notifications/flush' do
    it 'rejects a read-only token, then deletes only the caller notifications' do
      own = Fabricate(:notification, account: account, type: :follow, activity: Fabricate(:follow, account: actor, target_account: account))
      foreign = Fabricate(:notification, account: actor, type: :follow, activity: Fabricate(:follow, account: account, target_account: actor))

      post '/api/notifications/flush', params: { i: read_token }, as: :json

      expect(response).to have_http_status(403)
      expect(Notification.exists?(own.id)).to be(true)

      post '/api/notifications/flush', params: { i: write_token }, as: :json

      expect(response).to have_http_status(204)
      expect(Notification.exists?(own.id)).to be(false)
      expect(Notification.exists?(foreign.id)).to be(true)
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
