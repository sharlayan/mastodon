# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Chat voice calls' do
  include_context 'with an open chat policy'
  include_context 'with API authentication', oauth_scopes: 'read write'

  let(:relay) { FakeVoiceRelay.new.install }
  let(:owner) { Fabricate(:account) }
  let(:room) do
    Sharlayan::ChatService.new.create_conversation(owner, type: :group, title: 'Room').tap do |conversation|
      conversation.memberships.create!(account: user.account, role: :member)
    end
  end

  around { |example| ClimateControl.modify(OC_ROLEPLAY_OPTION: 'false') { example.run } }

  before do
    Setting.chat_enabled = true
    Setting.voice_call_enabled = true
  end

  after do
    Setting.chat_enabled = false
    Setting.voice_call_enabled = false
  end

  it 'reports availability, joins a call and lists call states of own rooms only' do
    get '/api/v1/chat/settings', headers: headers
    expect(response.parsed_body['voice_calls']).to be false

    get "/api/v1/chat/conversations/#{room.id}/voice", headers: headers
    expect(response.parsed_body).to include('available' => false, 'active' => false)

    relay.provider
    get '/api/v1/chat/settings', headers: headers
    expect(response.parsed_body).to include('voice_calls' => true, 'voice_call_screen_share' => true)

    post "/api/v1/chat/conversations/#{room.id}/voice/join", headers: headers
    expect(response).to have_http_status(200)
    expect(response.parsed_body).to include('url' => 'wss://cb6e6126.ngrok.io/voice-signal', 'token' => "lk-token-#{user.account.id}", 'max_participants' => 10)
    expect(response.parsed_body['ice_servers']).to eq [{ 'urls' => ['turn:turn.example.org:3478'], 'username' => 'u', 'credential' => 'c' }]

    other_room = Sharlayan::ChatService.new.create_conversation(owner, type: :group, title: 'Other')
    get '/api/v1/chat/voice_states', params: { conversation_ids: [room.id, other_room.id] }, headers: headers
    expect(response.parsed_body.pluck('conversation_id')).to eq [room.id.to_s]
    expect(response.parsed_body.first).to include('available' => true, 'max_participants' => 10)

    post "/api/v1/chat/conversations/#{room.id}/voice/status", params: { session_id: 'PA_1', mic_muted: true, deafened: false }, headers: headers
    expect(response.parsed_body).to eq('accepted' => true)
  end

  it 'lists call participants with their accounts' do
    relay.provider
    post "/api/v1/chat/conversations/#{room.id}/voice/join", headers: headers
    relay.participants = [relay.participant(user.account)]
    Sharlayan::VoiceCallService.new.poll_events(relay.provider)
    get '/api/v1/chat/voice_states', params: { conversation_ids: [room.id] }, headers: headers
    expect(response.parsed_body.first['participants']).to contain_exactly(a_hash_including('account_id' => user.account.id.to_s, 'account' => a_hash_including('id' => user.account.id.to_s)))
  end

  it 'refuses accounts whose role does not allow voice calls' do
    relay.provider
    UserRole.everyone.update!(extra_permissions: UserRole::EXTRA_FLAGS[:join_voice_calls])

    get '/api/v1/chat/settings', headers: headers
    expect(response.parsed_body).to include('voice_calls' => true, 'voice_call_screen_share' => false)

    UserRole.everyone.update!(extra_permissions: 0)
    get '/api/v1/chat/settings', headers: headers
    expect(response.parsed_body).to include('voice_calls' => false, 'voice_call_screen_share' => false)

    post "/api/v1/chat/conversations/#{room.id}/voice/join", headers: headers
    expect(response).to have_http_status(422)
    expect(response.parsed_body).to eq('error' => 'VOICE_CALL_UNAVAILABLE')
  end

  it 'maps relay failures and rejects moderation by members' do
    relay.provider
    relay.full = true
    post "/api/v1/chat/conversations/#{room.id}/voice/join", headers: headers
    expect(response).to have_http_status(503)
    expect(response.parsed_body).to eq('error' => 'VOICE_RELAY_CAPACITY_EXCEEDED')

    relay.full = false
    relay.fail_with = [403, { code: 'CLIENT_DISABLED' }]
    post "/api/v1/chat/conversations/#{room.id}/voice/join", headers: headers
    expect(response.parsed_body).to eq('error' => 'VOICE_RELAY_REVOKED')

    relay.fail_with = nil
    post "/api/v1/chat/conversations/#{room.id}/voice/kick", params: { account_id: owner.id }, headers: headers
    expect(response).to have_http_status(409)

    room.update!(archived_at: Time.now.utc)
    post "/api/v1/chat/conversations/#{room.id}/voice/join", headers: headers
    expect(response).to have_http_status(422)
    expect(response.parsed_body).to eq('error' => 'VOICE_CALL_UNAVAILABLE')
  end

  it 'hides rooms the account does not belong to' do
    stranger_room = Sharlayan::ChatService.new.create_conversation(owner, type: :group, title: 'Private')

    post "/api/v1/chat/conversations/#{stranger_room.id}/voice/join", headers: headers
    expect(response).to have_http_status(404)
  end

  it 'rate limits voice call requests per account' do
    relay.provider
    post "/api/v1/chat/conversations/#{room.id}/voice/join", headers: headers

    29.times { post "/api/v1/chat/conversations/#{room.id}/voice/status", params: { session_id: 'PA_1', mic_muted: true, deafened: false }, headers: headers }
    expect(response).to have_http_status(200)

    post "/api/v1/chat/conversations/#{room.id}/voice/status", params: { session_id: 'PA_1', mic_muted: true, deafened: false }, headers: headers
    expect(response).to have_http_status(429)
  end
end
