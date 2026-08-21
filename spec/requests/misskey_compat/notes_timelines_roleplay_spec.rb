# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat roleplay timelines' do
  let(:user)  { Fabricate(:user) }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read').token }
  let!(:status) { Fabricate(:status, account: Fabricate(:account)) }

  before do
    Setting.misskey_compat_enabled = true
    Setting.local_live_feed_access = 'disabled'
    Setting.remote_live_feed_access = 'disabled'
    Setting.roleplay_disable_local_timeline = false
    Setting.roleplay_hide_public_timelines_from_admins = false
  end

  after { Setting.misskey_compat_enabled = false }

  around do |example|
    ClimateControl.modify OC_ROLEPLAY_OPTION: 'true' do
      example.run
    end
  end

  it 'returns empty local, hybrid, and global timelines' do
    %w(local-timeline hybrid-timeline global-timeline).each do |timeline|
      post "/api/notes/#{timeline}", params: { i: token }, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to eq([])
    end
  end

  it 'allows a user with feed-view permission to read the local timeline' do
    user.update!(role: Fabricate(:user_role, permissions: UserRole::FLAGS[:view_feeds]))

    post '/api/notes/local-timeline', params: { i: token }, as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body.pluck(:id)).to include(MisskeyCompat::MiId.encode(status.id))
  end

  it 'hides timelines from a permitted user when the hard-hide option is enabled' do
    user.update!(role: Fabricate(:user_role, permissions: UserRole::FLAGS[:view_feeds]))
    Setting.roleplay_hide_public_timelines_from_admins = true

    post '/api/notes/local-timeline', params: { i: token }, as: :json

    expect(response).to have_http_status(200)
    expect(response.parsed_body).to be_empty
  end
end
