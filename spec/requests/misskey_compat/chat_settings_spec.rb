# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Misskey chat account settings' do
  let(:user) { Fabricate(:user) }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write') }

  before do
    Setting.misskey_compat_enabled = true
    Setting.chat_enabled = true
  end

  after do
    Setting.misskey_compat_enabled = false
    Setting.chat_enabled = false
  end

  it 'advertises chat availability so compatible clients enable the composer' do
    post '/api/i', params: { i: token.token }, as: :json
    expect(response.parsed_body.dig(:policies, :chatAvailability)).to eq('available')

    Setting.chat_enabled = false
    post '/api/i', params: { i: token.token }, as: :json
    expect(response.parsed_body.dig(:policies, :chatAvailability)).to eq('unavailable')
  end

  it 'persists chatScope and distributes the changed actor policy' do
    expect do
      post '/api/i/update', params: { i: token.token, chatScope: 'following' }, as: :json
    end.to change(ActivityPub::UpdateDistributionWorker.jobs, :size).by(1)

    expect(response).to have_http_status(200)
    expect(response.parsed_body[:chatScope]).to eq('following')
    expect(user.reload.settings[:chat_policy]).to eq('following')
  end

  it 'rejects invalid chat policies before applying other profile changes' do
    post '/api/i/update', params: { i: token.token, chatScope: 'invalid', name: 'Should not change' }, as: :json

    expect(response).to have_http_status(400)
    expect(user.account.reload.display_name).to_not eq('Should not change')
  end
end
