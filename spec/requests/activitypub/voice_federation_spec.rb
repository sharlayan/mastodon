# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ActivityPub voice call federation' do
  include_context 'with an open chat policy'

  let(:relay) { FakeVoiceRelay.new.install }
  let(:owner) { Fabricate(:user).account }
  let(:guest) { Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/guest', inbox_url: 'https://remote.test/users/guest/inbox') }
  let(:stranger) { Fabricate(:account, domain: 'other.test', uri: 'https://other.test/users/stranger', inbox_url: 'https://other.test/users/stranger/inbox') }
  let(:room) do
    Sharlayan::ChatService.new.create_conversation(owner, type: :group, title: 'Room').tap do |conversation|
      conversation.memberships.create!(account: guest, role: :member)
    end
  end
  let(:room_uri) { "https://cb6e6126.ngrok.io/chat/rooms/#{room.id}" }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }

  around { |example| ClimateControl.modify(OC_ROLEPLAY_OPTION: 'false') { example.run } }

  before do
    Setting.chat_enabled = true
    Setting.chat_federation_enabled = true
    Setting.voice_call_enabled = true
    Setting.voice_call_federation_host_enabled = true
    relay.provider
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_federation_enabled = false
    Setting.voice_call_enabled = false
    Setting.voice_call_federation_host_enabled = false
  end

  def token_request(account, body)
    post '/livekit/federation/token', params: body.to_json, headers: json_headers.dup, sign_with: account
  end

  it 'issues a join token to a remote member with the signaling address of this server' do
    token_request(guest, { room: room_uri, canScreenShare: false })

    expect(response).to have_http_status(200)
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(response.parsed_body).to include(
      'url' => 'https://cb6e6126.ngrok.io/livekit', 'token' => "lk-token-#{guest.id}", 'mediaProvider' => 'https://voice.example.org',
      'iceServers' => [{ 'urls' => ['turn:turn.example.org:3478'], 'username' => 'u', 'credential' => 'c' }], 'participants' => []
    )
    expect(response.parsed_body['updatedAt']).to be_a(Integer)
    expect(relay.join_bodies.last).to include('identity' => guest.uri, 'userId' => guest.id.to_s, 'allowScreenShare' => false)

    token_request(guest, { room: room_uri, canScreenShare: true, includeIceServers: false })
    expect(response.parsed_body).to include('iceServers' => nil)
    expect(relay.join_bodies.last).to include('allowScreenShare' => true)

    get "/livekit/federation/token?room=#{CGI.escape(room_uri)}", headers: {}, sign_with: guest
    expect(response.parsed_body).to eq('includeIceServers' => true)
  end

  it 'accepts status reports from remote participants' do
    token_request(guest, { room: room_uri })

    post '/livekit/federation/status', params: { room: room_uri, sessionId: 'PA_9', micMuted: true, deafened: false }.to_json, headers: json_headers.dup, sign_with: guest
    expect(response).to have_http_status(200)
    expect(response.parsed_body).to eq({})

    post '/livekit/federation/status', params: { room: room_uri, sessionId: 'PA_9', micMuted: 'yes', deafened: false }.to_json, headers: json_headers.dup, sign_with: guest
    expect(response).to have_http_status(400)
  end

  it 'refuses unsigned requests, outsiders, blocked servers and malformed rooms' do
    post '/livekit/federation/token', params: { room: room_uri }.to_json, headers: json_headers.dup
    expect(response).to have_http_status(401)

    token_request(stranger, { room: room_uri })
    expect(response).to have_http_status(403)

    token_request(guest, { room: "#{room_uri}?x=1" })
    expect(response).to have_http_status(403)

    token_request(guest, { room: 7 })
    expect(response).to have_http_status(400)

    DomainBlock.create!(domain: 'remote.test', severity: :suspend)
    token_request(guest, { room: room_uri })
    expect(response).to have_http_status(403)
  end

  it 'answers 404 while this server does not provide calls to other servers' do
    Setting.voice_call_federation_host_enabled = false
    token_request(guest, { room: room_uri })
    expect(response).to have_http_status(404)
  end
end
