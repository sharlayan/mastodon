# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ActivityPub chat messages' do
  let(:owner) { Fabricate(:user).account }
  let(:member) { Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/member', inbox_url: 'https://remote.test/users/member/inbox') }
  let(:stranger) { Fabricate(:account, domain: 'other.test', uri: 'https://other.test/users/stranger', inbox_url: 'https://other.test/users/stranger/inbox') }
  let(:service) { Sharlayan::ChatService.new }
  let(:conversation) { service.create_conversation(owner, type: :group, account_ids: [member.id], title: 'Room') }
  let(:message) { service.create_message(owner, conversation, text: 'secret') }

  before do
    conversation.memberships.find_or_create_by!(account: member)
    Setting.chat_enabled = true
    Setting.chat_federation_enabled = true
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_federation_enabled = false
  end

  it 'returns 401 without a signature header' do
    get "/chat/messages/#{message.id}"

    expect(response).to have_http_status(401)
  end

  it 'returns 404 to an unrelated signed actor' do
    get "/chat/messages/#{message.id}", headers: { 'Accept' => 'application/activity+json' }, sign_with: stranger

    expect(response).to have_http_status(404)
  end

  it 'returns the Note to a conversation member' do
    get "/chat/messages/#{message.id}", headers: { 'Accept' => 'application/activity+json' }, sign_with: member

    expect(response).to have_http_status(200)
    expect(response.parsed_body['type']).to eq('Note')
    expect(response.parsed_body['_misskey_talk']).to be(true)
    expect(response.headers['Cache-Control']).to eq('private, no-store')
    expect(response.media_type).to eq('application/activity+json')
    expect(response.parsed_body['@context']).to eq(Sharlayan::ChatFederation::Payload::CONTEXT.as_json)
    expect(response.parsed_body).to include('context' => conversation.uri, '_misskey_chatRoom' => conversation.uri)
  end

  it 'returns a Tombstone for a deleted message' do
    message.update!(deleted_at: Time.current)

    get "/chat/messages/#{message.id}", headers: { 'Accept' => 'application/activity+json' }, sign_with: member

    expect(response).to have_http_status(200)
    expect(response.parsed_body).to include('type' => 'Tombstone', 'formerType' => 'Note')
  end
end
