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
end
