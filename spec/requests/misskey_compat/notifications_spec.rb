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
