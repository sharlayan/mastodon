# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey-compat channels/mute endpoint' do
  before { Setting.misskey_compat_enabled = true }
  after  { Setting.misskey_compat_enabled = false }

  describe 'POST /api/channels/mute/create' do
    it 'accepts the call as a no-op' do
      post '/api/channels/mute/create', params: { channelId: 'x' }, as: :json

      expect(response).to have_http_status(204)
    end
  end

  describe 'POST /api/channels/mute/delete' do
    it 'accepts the call as a no-op' do
      post '/api/channels/mute/delete', params: { channelId: 'x' }, as: :json

      expect(response).to have_http_status(204)
    end
  end
end
