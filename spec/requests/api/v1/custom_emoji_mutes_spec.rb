# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Custom emoji mutes' do
  let(:user)    { Fabricate(:user) }
  let(:scopes)  { 'read:mutes write:mutes' }
  let(:token)   { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: scopes) }
  let(:headers) { { 'Authorization' => "Bearer #{token.token}" } }

  describe 'POST /api/v1/custom_emoji_mutes' do
    it 'creates a mute' do
      post '/api/v1/custom_emoji_mutes', params: { prefix: 'blob' }, headers: headers

      expect(response).to have_http_status(200)
      expect(user.account.custom_emoji_mutes.pluck(:prefix)).to eq(['blob'])
    end

    it 'rejects creation beyond the per-account limit' do
      stub_const('CustomEmojiMute::PER_ACCOUNT_LIMIT', 1)
      user.account.custom_emoji_mutes.create!(prefix: 'existing')

      post '/api/v1/custom_emoji_mutes', params: { prefix: 'overflow' }, headers: headers

      expect(response).to have_http_status(422)
      expect(user.account.custom_emoji_mutes.count).to eq(1)
    end
  end
end
