# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ActivityPub chat room fetches' do
  let(:owner) { Fabricate(:user).account }
  let(:invitee) { Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/invitee', inbox_url: 'https://remote.test/users/invitee/inbox') }
  let(:stranger) { Fabricate(:account, domain: 'other.test', uri: 'https://other.test/users/stranger', inbox_url: 'https://other.test/users/stranger/inbox') }
  let(:service) { Sharlayan::ChatService.new }
  let(:conversation) { service.create_conversation(owner, type: :group, account_ids: [invitee.id], title: 'Remote room') }

  before do
    Setting.chat_enabled = true
    Setting.chat_federation_enabled = true
    conversation
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_federation_enabled = false
  end

  it 'returns 401 without a signature header, 404 to an unrelated signed actor, and the Group to a pending invitee' do
    get "/chat/rooms/#{conversation.id}"
    expect(response).to have_http_status(401)

    get "/chat/rooms/#{conversation.id}", headers: { 'Accept' => 'application/activity+json' }, sign_with: stranger
    expect(response).to have_http_status(404)

    get "/chat/rooms/#{conversation.id}", headers: { 'Accept' => 'application/activity+json' }, sign_with: invitee
    expect(response).to have_http_status(200)
    expect(response.parsed_body['type']).to eq('Group')
    expect(response.headers['Cache-Control']).to eq('private, no-store')
  end
end
