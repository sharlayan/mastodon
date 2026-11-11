# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::VoiceCallService do
  subject(:service) { described_class.new }

  include_context 'with an open chat policy'

  let(:relay) { FakeVoiceRelay.new.install }
  let!(:provider) { relay.provider }
  let(:owner) { Fabricate(:user).account }
  let(:member) { Fabricate(:user).account }
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
    state = described_class.state_for(room)
    expect(state).to include(active: true, available: true, updated_at: (allocation.updated_at.to_r * 1000).to_i)
    expect(state[:participants]).to contain_exactly(
      a_hash_including(identity: ActivityPub::TagManager.instance.uri_for(member), account_id: member.id.to_s, screen_sharing: false, mic_muted: true, deafened: false)
    )
    expect(state[:participants].first[:account]).to include(id: member.id.to_s, username: member.username)
  end

  it 'removes a participant whose membership ends and lets only the owner moderate' do
    service.join(member, room)
    relay.participants = [relay.participant(member)]
    service.poll_events(provider)

    expect { service.kick(member, room, owner) }.to raise_error(described_class::Forbidden)
    expect(service.mute(owner, room, member)).to be true
    expect(service.kick(owner, room, member)).to be true
    expect { service.join(member, room) }.to raise_error(described_class::Removed)

    service.end_call(VoiceCallAllocation.find_by!(chat_conversation: room))
    service.join(member, room)
    relay.participants = [relay.participant(member)]
    service.poll_events(provider)

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

  it 'confirms the end of a call the relay no longer accepts before opening a new one' do
    service.join(member, room)

    relay.join_error = [404, 'NOT_FOUND']
    service.join(member, room)
    expect(relay.called?(:delete, '/allocations/alloc-1')).to be true
    expect(VoiceCallAllocation.find_by!(chat_conversation: room).remote_id).to eq 'alloc-2'

    relay.lease_state = 'ending'
    service.join(member, room)
    expect(relay.called?(:delete, '/allocations/alloc-2')).to be true
    expect(VoiceCallAllocation.find_by!(chat_conversation: room)).to have_attributes(state: 'active', remote_id: 'alloc-3')
  end

  it 'closes calls on a relay that revoked this server and removes suspended members' do
    service.join(member, room)
    allocation = VoiceCallAllocation.find_by!(chat_conversation: room)

    relay.participants = [relay.participant(member)]
    member.suspend!
    service.poll_events(provider)
    expect(relay.kicked).to include(ActivityPub::TagManager.instance.uri_for(member))
    expect(allocation.reload.participants).to be_empty

    allocation.update_columns(renewed_at: 1.minute.ago)
    relay.fail_with = [403, { code: 'CLIENT_DISABLED' }]
    service.maintain
    expect(provider.reload).to have_attributes(validated: false, last_error: 'CLIENT_DISABLED', revoked?: true)
    expect(allocation.reload.state).to eq 'ending'

    relay.fail_with = nil
    service.maintain
    expect(allocation.reload.state).to eq 'ended'
  end

  it 'follows role permissions when issuing credentials' do
    role = Fabricate(:user_role, extra_permissions: UserRole::EXTRA_FLAGS[:join_voice_calls])
    UserRole.everyone.update!(extra_permissions: 0)

    expect { service.join(member, room) }.to raise_error(described_class::Unavailable)

    member.user.update!(role:)
    expect(service.join(member, room)).to include(allow_screen_share: false)
    expect(relay.join_bodies.last).to include('allowScreenShare' => false)

    owner.user.update!(role: Fabricate(:user_role, extra_permissions: UserRole::ExtraFlags::DEFAULT))
    expect(service.join(owner, room)).to include(allow_screen_share: true)

    Setting.voice_call_screen_share_enabled = false
    expect(service.join(owner, room)).to include(allow_screen_share: false)
  ensure
    Setting.voice_call_screen_share_enabled = true
  end

  it 'removes participants that lost the voice call permission and stops screen sharing for those that lost that permission' do
    role = Fabricate(:user_role, extra_permissions: UserRole::EXTRA_FLAGS[:join_voice_calls])
    service.join(member, room)
    UserRole.everyone.update!(extra_permissions: 0)
    member.user.update!(role:)
    owner.user.update!(role: Fabricate(:user_role, extra_permissions: UserRole::ExtraFlags::DEFAULT))

    relay.participants = [relay.participant(member, allowScreenShare: false), relay.participant(owner, session_id: 'PA_2', screenSharing: true)]
    service.poll_events(provider)
    expect(VoiceCallAllocation.find_by!(chat_conversation: room).participants.pluck('user_id')).to contain_exactly(member.id.to_s, owner.id.to_s)

    owner.user.update!(role:)
    relay.events = [{ 'allocationId' => 'alloc-1', 'generation' => VoiceCallAllocation.find_by!(chat_conversation: room).generation }]
    service.poll_events(provider)
    expect(relay.kicked).to be_empty
    expect(relay.restricted).to eq [ActivityPub::TagManager.instance.uri_for(owner)]
    expect(VoiceCallAllocation.find_by!(chat_conversation: room).participants.find { |participant| participant['user_id'] == owner.id.to_s })
      .to include('screen_sharing' => false, 'allow_screen_share' => false)

    member.user.update!(disabled: true)
    service.poll_events(provider)
    expect(relay.kicked).to eq [ActivityPub::TagManager.instance.uri_for(member)]
    expect(VoiceCallAllocation.find_by!(chat_conversation: room).participants.pluck('user_id')).to eq [owner.id.to_s]
  end

  it 'looks up the default role and domain blocks once per room when checking participants' do
    others = Array.new(5) { Fabricate(:user).account }
    guests = Array.new(3) { |index| Fabricate(:account, domain: 'remote.test', username: "guest#{index}") }
    (others + guests).each { |account| room.memberships.create!(account:, role: :member) }
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] unless payload[:cached] }

    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { service.send(:member_permissions, room.id) }

    expect(queries.grep(/FROM "user_roles"/).size).to be <= 1
    expect(queries.grep(/FROM "domain_blocks"/).size).to be <= 1
  end

  it 'admits members from other servers only while this server provides calls to them' do
    guest = Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/guest', inbox_url: 'https://remote.test/users/guest/inbox')
    room.memberships.create!(account: guest, role: :member)
    Setting.chat_federation_enabled = true

    expect { service.join(guest, room) }.to raise_error(described_class::Unavailable)

    Setting.voice_call_federation_host_enabled = true
    expect(service.join(guest, room, screen_share: false)).to include(identity: guest.uri, allow_screen_share: false)
    expect(relay.join_bodies.last).to include('identity' => guest.uri, 'userId' => guest.id.to_s)

    relay.participants = [relay.participant(member), relay.participant(guest, session_id: 'PA_2')]
    service.poll_events(provider)
    expect(VoiceCallAllocation.find_by!(chat_conversation: room).participants.pluck('user_id')).to contain_exactly(member.id.to_s, guest.id.to_s)

    Setting.voice_call_federation_host_enabled = false
    relay.events = [{ 'allocationId' => 'alloc-1', 'generation' => VoiceCallAllocation.find_by!(chat_conversation: room).generation }]
    service.poll_events(provider)
    expect(relay.kicked).to eq [guest.uri]
  ensure
    Setting.chat_federation_enabled = false
    Setting.voice_call_federation_host_enabled = false
  end

  it 'keeps direct chats with members from other servers out of calls' do
    guest = Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/guest', inbox_url: 'https://remote.test/users/guest/inbox')
    direct = ChatConversation.create!(conversation_type: :direct, direct_key: [owner.id, guest.id].sort.join(':'))
    direct.memberships.create!([{ account: owner }, { account: guest }])
    Setting.chat_federation_enabled = true
    Setting.voice_call_federation_host_enabled = true

    expect(described_class.available?(direct)).to be false
    expect(Sharlayan::VoiceCallFederation.hosted_room?(direct)).to be false
    expect(Sharlayan::VoiceCallFederation.hosted_room?(room)).to be true
  ensure
    Setting.chat_federation_enabled = false
    Setting.voice_call_federation_host_enabled = false
  end

  it 'reports a relay as revoked only when it disabled this server' do
    allow(relay).to(receive(:capacity).and_wrap_original { |original| original.call.merge('accepting' => false) })
    expect { service.join(member, room) }.to raise_error(an_object_having_attributes(code: 'PROVIDER_UNAVAILABLE'))

    allow(relay).to(receive(:capacity).and_wrap_original { |original| original.call.merge('enabled' => false, 'accepting' => false) })
    expect { service.join(member, room) }.to raise_error(an_object_having_attributes(code: 'CLIENT_DISABLED'))
  end

  it 'skips a failing relay for a short while and validates status reports' do
    relay.fail_with = [503, { code: 'PROVIDER_UNAVAILABLE' }]
    expect { service.join(member, room) }.to raise_error(an_object_having_attributes(code: 'PROVIDER_UNAVAILABLE'))
    expect { service.join(member, room) }.to raise_error(an_object_having_attributes(code: 'PROVIDER_UNAVAILABLE'))
    expect(relay.calls.count([:get, '/capacity'])).to eq 1

    expect { service.report_status(member, room, session_id: ['x'], mic_muted: true, deafened: false) }.to raise_error(Mastodon::InvalidParameterError)
  end
end
