# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat roleplay timelines' do
  let(:user)  { Fabricate(:user) }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read').token }

  before do
    Setting.misskey_compat_enabled = true
    Setting.local_live_feed_access = 'authenticated'
    Setting.remote_live_feed_access = 'authenticated'
    Fabricate(:status, account: Fabricate(:account))
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
end
