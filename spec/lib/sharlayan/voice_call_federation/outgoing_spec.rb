# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::VoiceCallFederation::Outgoing do
  include_context 'with an open chat policy'

  let(:relay) { FakeVoiceRelay.new.install }
  let(:owner) { Fabricate(:user).account }
  let(:guest) { Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/guest', inbox_url: 'https://remote.test/users/guest/inbox') }
  let(:room) do
    Sharlayan::ChatService.new.create_conversation(owner, type: :group, title: 'Room').tap do |conversation|
      conversation.memberships.create!(account: guest, role: :member)
    end
  end
  let(:participants) do
    [
      { 'identity' => ActivityPub::TagManager.instance.uri_for(owner), 'user_id' => owner.id.to_s, 'screen_sharing' => true, 'mic_muted' => false, 'deafened' => false },
      { 'identity' => guest.uri, 'user_id' => guest.id.to_s, 'screen_sharing' => false, 'mic_muted' => true, 'deafened' => false },
    ]
  end
  let!(:allocation) do
    VoiceCallAllocation.create!(chat_conversation: room, voice_relay_provider: relay.provider, generation: 'g1', remote_id: 'alloc-1', room_key: 'k', state: 'active', slots: 6, participants:)
  end

  around { |example| ClimateControl.modify(OC_ROLEPLAY_OPTION: 'false') { example.run } }

  before do
    Setting.chat_enabled = true
    Setting.chat_federation_enabled = true
    Setting.voice_call_enabled = true
    Setting.voice_call_federation_host_enabled = true
    %w(gate sent stamp).each { |kind| redis.del("voice_call:federation:#{kind}:#{room.id}") }
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_federation_enabled = false
    Setting.voice_call_enabled = false
    Setting.voice_call_federation_host_enabled = false
  end

  def delivered_payloads
    ActivityPub::DeliveryWorker.jobs.map { |job| JSON.parse(job['args'].first) }
  end

  it 'sends the call participants to remote members once per change and stamps them in order' do
    described_class.publish(room)

    payload = delivered_payloads.last
    expect(ActivityPub::DeliveryWorker.jobs.last['args'].drop(1)).to eq [owner.id, guest.inbox_url]
    expect(payload).to include('type' => 'Update', 'actor' => ActivityPub::TagManager.instance.uri_for(owner))
    expect(payload['object']).to include(
      'id' => "https://cb6e6126.ngrok.io/chat/rooms/#{room.id}/voice", 'type' => 'ChatRoomVoiceState', 'room' => "https://cb6e6126.ngrok.io/chat/rooms/#{room.id}"
    )
    expect(payload['object']['participants']).to contain_exactly(
      { 'id' => ActivityPub::TagManager.instance.uri_for(owner), 'screenSharing' => true, 'micMuted' => false, 'deafened' => false },
      { 'id' => guest.uri, 'screenSharing' => false, 'micMuted' => true, 'deafened' => false }
    )
    expect(payload['@context'].last).to include('cherrypick' => 'https://kokonect.link/ns#')

    described_class.publish(room)
    expect(ActivityPub::DeliveryWorker.jobs.size).to eq 1

    allocation.update!(participants: participants.first(1))
    described_class.publish(room)
    expect(ActivityPub::DeliveryWorker.jobs.size).to eq 1
    expect(VoiceCallFederationWorker.jobs.last['args']).to eq [room.id]

    allocation.update!(state: 'ended', participants: [])
    described_class.publish(room)
    expect(delivered_payloads.last['object']['participants']).to eq []
    expect(Time.zone.parse(delivered_payloads.last['object']['updated'])).to be > Time.zone.parse(payload['object']['updated'])
  end

  it 'resends an unchanged call after the resend interval and stays quiet when disabled' do
    described_class.publish(room)
    redis.del("voice_call:federation:gate:#{room.id}")

    travel_to(Time.now.utc + described_class::RESEND_INTERVAL + 1.second) do
      described_class.publish(room)
    end
    expect(ActivityPub::DeliveryWorker.jobs.size).to eq 2

    Setting.voice_call_federation_host_enabled = false
    described_class.schedule(room)
    expect(VoiceCallFederationWorker.jobs).to be_empty
  end

  it 'publishes only for local rooms with members on other servers' do
    lonely = Sharlayan::ChatService.new.create_conversation(owner, type: :group, title: 'Lonely')

    described_class.schedule(lonely)
    expect(VoiceCallFederationWorker.jobs).to be_empty

    described_class.schedule(room)
    expect(VoiceCallFederationWorker.jobs.pluck('args')).to eq [[room.id]]
  end
end
