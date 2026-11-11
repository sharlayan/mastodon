# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::VoiceCallService do
  subject(:service) { described_class.new }

  include_context 'with an open chat policy'

  let(:relay) { FakeVoiceRelay.new.install }
  let!(:provider) { relay.provider }
  let(:owner) { Fabricate(:account) }
  let(:member) { Fabricate(:account) }
  let(:room) do
    Sharlayan::ChatService.new.create_conversation(owner, type: :group, title: 'Room').tap do |conversation|
      conversation.memberships.create!(account: member, role: :member)
    end
  end

  around { |example| ClimateControl.modify(OC_ROLEPLAY_OPTION: 'false') { example.run } }

  before do
    Setting.chat_enabled = true
    Setting.voice_call_enabled = true
    Setting.voice_call_max_participants = 6
  end

  after do
    Setting.chat_enabled = false
    Setting.voice_call_enabled = false
    Setting.voice_call_max_participants = 10
  end

  it 'reserves the room on the least loaded relay and issues credentials for members' do
    busy = FakeVoiceRelay.new('https://busy.example.org', reserved_slots: 90).install
    busy.provider

    credentials = service.join(member, room)

    expect(credentials).to include(
      url: 'wss://cb6e6126.ngrok.io/voice-signal', token: "lk-token-#{member.id}", media_provider: 'https://voice.example.org',
      identity: ActivityPub::TagManager.instance.uri_for(member), allow_screen_share: true, max_participants: 6,
      ice_servers: [{ urls: ['turn:turn.example.org:3478'], username: 'u', credential: 'c' }],
      screen_share_limits: { 'maxWidth' => 1920, 'maxHeight' => 1080, 'maxFrameRate' => 30, 'maxBitrate' => 2_500_000 }
    )
    expect(busy.called?(:post, '/allocations')).to be false

    allocation = VoiceCallAllocation.find_by!(chat_conversation: room)
    expect(allocation).to have_attributes(voice_relay_provider: provider, state: 'active', slots: 6, room_key: "https://cb6e6126.ngrok.io/chat/rooms/#{room.id}", remote_id: 'alloc-1')
    expect(VoiceCallEventsWorker).to have_enqueued_sidekiq_job(provider.id)

    service.join(owner, room)
    expect(relay.allocations.size).to eq 1
    expect(relay.called?(:post, '/allocations/alloc-1/lease')).to be true
  end

  it 'refuses non-members, unavailable rooms and full relays' do
    expect { service.join(Fabricate(:account), room) }.to raise_error(described_class::Forbidden)

    room.update!(archived_at: Time.now.utc)
    expect { service.join(member, room) }.to raise_error(described_class::Unavailable)
    room.update!(archived_at: nil)

    relay.full = true
    expect { service.join(member, room) }.to raise_error(Sharlayan::VoiceRelay::Error) { |error| expect(error.code).to eq 'CAPACITY_EXCEEDED' }

    Setting.voice_call_enabled = false
    expect { service.join(member, room) }.to raise_error(described_class::Unavailable)
  end

  it 'starts a new generation after the relay ended the previous call and recovers a pending reservation' do
    service.join(member, room)
    first = VoiceCallAllocation.find_by!(chat_conversation: room).generation

    relay.lease_state = 'ended'
    service.join(member, room)
    relay.lease_state = 'active'
    allocation = VoiceCallAllocation.find_by!(chat_conversation: room)
    expect(allocation.generation).to_not eq first
    expect(allocation.remote_id).to eq 'alloc-2'

    allocation.update!(state: 'pending', generation: 'pending-generation', remote_id: nil)
    relay.allocations['alloc-9'] = relay.allocations['alloc-2'].merge('id' => 'alloc-9', 'generation' => 'pending-generation')
    service.join(member, room)
    expect(allocation.reload).to have_attributes(state: 'active', remote_id: 'alloc-9')
    expect(relay.called?(:get, '/allocations')).to be true
  end

  it 'refreshes participants from the event feed, removes non-members and broadcasts the state' do
    service.join(member, room)
    stranger = Fabricate(:account)
    relay.participants = [relay.participant(member, micMuted: true), relay.participant(stranger, session_id: 'PA_2')]
    allow(redis).to receive(:publish).and_call_original

    expect(service.poll_events(provider)).to be true

    allocation = VoiceCallAllocation.find_by!(chat_conversation: room)
    expect(allocation.participants.pluck('user_id', 'mic_muted')).to eq [[member.id.to_s, true]]
    expect(relay.kicked).to eq [ActivityPub::TagManager.instance.uri_for(stranger)]
    expect(provider.reload.events_cursor).to be_present
    expect(redis).to have_received(:publish).with("timeline:#{owner.id}", a_string_including('chat.voice_state'))
    expect(described_class.state_for(room)).to include(active: true, available: true, participants: [{ account_id: member.id.to_s, screen_sharing: false, mic_muted: true, deafened: false }])
  end

  it 'removes a participant whose membership ends and lets only the owner moderate' do
    service.join(member, room)
    relay.participants = [relay.participant(member)]
    service.poll_events(provider)

    expect { service.kick(member, room, owner) }.to raise_error(described_class::Forbidden)
    expect(service.mute(owner, room, member)).to be true

    room.memberships.find_by!(account: member).destroy!
    expect(VoiceCallRevocationWorker).to have_enqueued_sidekiq_job(room.id, member.id)

    service.revoke(room.id, member.id)
    expect(relay.kicked).to include(ActivityPub::TagManager.instance.uri_for(member))
    expect(VoiceCallAllocation.find_by!(chat_conversation: room).participants).to be_empty
  end

  it 'ends calls of deleted rooms and disabled features during maintenance and prunes old records' do
    service.join(member, room)
    allocation = VoiceCallAllocation.find_by!(chat_conversation: room)
    Sharlayan::ChatService.new.destroy_conversation(owner, room)
    expect(VoiceCallEndWorker).to have_enqueued_sidekiq_job(allocation.id)
    expect(allocation.reload.chat_conversation_id).to be_nil

    service.maintain
    expect(allocation.reload.state).to eq 'ended'
    expect(relay.allocations['alloc-1']['state']).to eq 'ended'

    allocation.update_columns(updated_at: 8.days.ago)
    service.maintain
    expect(VoiceCallAllocation).to_not exist(allocation.id)
  end
end
