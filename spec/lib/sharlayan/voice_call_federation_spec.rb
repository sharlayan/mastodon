# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::VoiceCallFederation do
  include_context 'with an open chat policy'

  let(:host) { Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/host', inbox_url: 'https://remote.test/users/host/inbox') }
  let(:other) { Fabricate(:account, domain: 'other.test', uri: 'https://other.test/users/other') }
  let(:member) { Fabricate(:user).account }
  let(:stranger) { Fabricate(:user).account }
  let(:mirror) do
    ChatConversation.create!(conversation_type: :group, owner_account: host, title: 'Mirror', uri: 'https://remote.test/chat/rooms/9').tap do |record|
      record.memberships.create!(account: host, role: :owner)
      record.memberships.create!(account: member)
    end
  end
  let(:member_uri) { ActivityPub::TagManager.instance.uri_for(member) }
  let(:now_ms) { (Time.now.to_f * 1000).to_i }
  let(:token) { "e30.#{Base64.urlsafe_encode64({ sub: member_uri, video: { room: 'room-9', roomJoin: true } }.to_json, padding: false)}.sig" }
  let(:token_response) do
    {
      url: 'https://remote.test/livekit', token:, updatedAt: now_ms, mediaProvider: 'https://voice.example.org',
      iceServers: [{ urls: ['turn:turn.example.org:3478'], username: 'u', credential: 'c' }],
      participants: [{ identity: host.uri, screenSharing: true }, { identity: ActivityPub::TagManager.instance.uri_for(stranger), screenSharing: false }]
    }
  end

  around { |example| ClimateControl.modify(OC_ROLEPLAY_OPTION: 'false') { example.run } }

  before do
    Setting.chat_enabled = true
    Setting.chat_federation_enabled = true
    Setting.voice_call_remote_join_enabled = true
    redis.del('voice_call:remote_unsupported:remote.test')
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_federation_enabled = false
    Setting.voice_call_remote_join_enabled = false
  end

  def voice_state_update(participants:, updated: Time.now.utc, room: mirror.uri, actor: host)
    {
      'type' => 'Update', 'actor' => actor.uri,
      'object' => { 'id' => "#{room}/voice", 'type' => 'ChatRoomVoiceState', 'room' => room, 'participants' => participants, 'updated' => updated.iso8601(3) }
    }
  end

  describe 'incoming call states' do
    it 'stores the newest state from the room owner, keeping only known participants' do
      allow(redis).to receive(:publish).and_call_original
      update = voice_state_update(participants: [{ 'id' => host.uri, 'screenSharing' => false, 'micMuted' => true }, { 'id' => member_uri, 'screenSharing' => false }, { 'id' => 'https://unknown.test/users/x', 'screenSharing' => false }])

      ActivityPub::Activity::Update.new(update, host).perform

      state = Sharlayan::VoiceCallService.state_for(mirror)
      expect(state).to include(available: true, active: true)
      expect(state[:participants].map { |participant| [participant[:account_id], participant[:mic_muted]] }).to contain_exactly([host.id.to_s, true], [member.id.to_s, false])
      expect(redis).to have_received(:publish).with("timeline:#{member.id}", a_string_including('chat.voice_state'))

      ActivityPub::Activity::Update.new(voice_state_update(participants: [], updated: 1.minute.ago), host).perform
      expect(Sharlayan::VoiceCallService.state_for(mirror)[:active]).to be true

      ActivityPub::Activity::Update.new(voice_state_update(participants: []), host).perform
      expect(Sharlayan::VoiceCallService.state_for(mirror)[:active]).to be false
    end

    it 'rejects states from other actors, other servers, the far future and while remote calls are off' do
      expect(Sharlayan::VoiceCallFederation::Incoming.handle(voice_state_update(participants: [], actor: other), other)).to eq 'skip: voice state is not on the sender server'
      expect(Sharlayan::VoiceCallFederation::Incoming.handle(voice_state_update(participants: [], room: 'https://remote.test/chat/rooms/9?x'), host)).to eq 'skip: voice state is not on the sender server'
      expect(Sharlayan::VoiceCallFederation::Incoming.handle(voice_state_update(participants: [], updated: 1.hour.from_now), host)).to eq 'ahead: voice state'
      expect(Sharlayan::VoiceCallFederation::Incoming.handle(voice_state_update(participants: [{ 'id' => host.uri }]), host)).to eq 'skip: invalid participants'

      Setting.voice_call_remote_join_enabled = false
      expect(Sharlayan::VoiceCallFederation::Incoming.handle(voice_state_update(participants: []), host)).to eq 'skip: remote voice calls disabled'
      expect(VoiceCallRemoteState.count).to eq 0
    end
  end

  describe 'joining' do
    let(:service) { Sharlayan::VoiceCallService.new }

    it 'asks the room owner server for a token as the member and routes signaling through this server' do
      request = stub_request(:post, 'https://remote.test/livekit/federation/token').to_return(status: 200, body: token_response.to_json, headers: { 'Content-Type' => 'application/json' })

      credentials = service.join(member, mirror)

      expect(request.with { |req| req.headers['Signature'].include?(member_uri) && JSON.parse(req.body) == { 'room' => mirror.uri, 'canScreenShare' => true } }).to have_been_made
      session = VoiceCallRemoteSession.sole
      expect(session).to have_attributes(account_id: member.id, identity: member_uri, room_name: 'room-9', origin: 'https://remote.test')
      expect(credentials).to include(
        url: "wss://cb6e6126.ngrok.io/voice-signal/remote/#{session.id}", token:, identity: member_uri, media_provider: 'https://voice.example.org',
        ice_servers: [{ urls: ['turn:turn.example.org:3478'], username: 'u', credential: 'c' }], allow_screen_share: true
      )
      expect(service.join(member, mirror)[:url]).to end_with("/remote/#{session.id}")
      expect(VoiceCallRemoteSession.sole.id).to eq session.id
      expect(Sharlayan::VoiceCallService.state_for(mirror)[:participants].pluck(:account_id)).to eq [host.id.to_s]

      status = stub_request(:post, 'https://remote.test/livekit/federation/status').to_return(status: 200, body: '{}')
      expect(service.report_status(member, mirror, session_id: 'PA_1', mic_muted: true, deafened: false)).to be true
      expect(status.with(body: { room: mirror.uri, sessionId: 'PA_1', micMuted: true, deafened: false }.to_json)).to have_been_made
    end

    it 'refuses responses that point somewhere else and remembers servers without calls' do
      stub_request(:post, 'https://remote.test/livekit/federation/token').to_return(status: 200, body: token_response.merge(url: 'https://evil.test/livekit').to_json)
      expect { service.join(member, mirror) }.to raise_error(Sharlayan::VoiceRelay::Error) { |error| expect(error.code).to eq 'REMOTE_HOST_UNREACHABLE' }

      stub_request(:post, 'https://remote.test/livekit/federation/token').to_return(status: 403)
      expect { service.join(member, mirror) }.to raise_error(Sharlayan::VoiceCallService::Unavailable)

      stub_request(:post, 'https://remote.test/livekit/federation/token').to_return(status: 404)
      expect { service.join(member, mirror) }.to raise_error(Sharlayan::VoiceRelay::Error) { |error| expect(error.code).to eq 'REMOTE_HOST_UNSUPPORTED' }
      expect { service.join(member, mirror) }.to raise_error(Sharlayan::VoiceRelay::Error) { |error| expect(error.code).to eq 'REMOTE_HOST_UNSUPPORTED' }
      expect(a_request(:post, 'https://remote.test/livekit/federation/token')).to have_been_made.times(3)
    end

    it 'lets only members join and only while remote calls are allowed' do
      expect { service.join(stranger, mirror) }.to raise_error(Sharlayan::VoiceCallService::Forbidden)

      Setting.voice_call_remote_join_enabled = false
      expect { service.join(member, mirror) }.to raise_error(Sharlayan::VoiceCallService::Unavailable)
      expect(Sharlayan::VoiceCallService.state_for(mirror)[:available]).to be false
    end
  end
end
