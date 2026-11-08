# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::ChatService do
  let(:service) { described_class.new }
  let(:local) { Fabricate(:user).account }
  let(:owner) { Fabricate(:account, domain: 'owner.test', uri: 'https://owner.test/users/owner', inbox_url: 'https://owner.test/users/owner/inbox', can_chat: true) }
  let(:known) { Fabricate(:account, domain: 'member.test', uri: 'https://member.test/users/known', inbox_url: 'https://member.test/users/known/inbox', can_chat: true) }
  let(:room) do
    service.receive_invite(local, owner, room_uri: 'https://owner.test/chat/rooms/abc', title: 'Remote room').tap { |invitation| service.accept_invitation(local, invitation) }.chat_conversation
  end
  let(:fetcher) { instance_double(ActivityPub::FetchRemoteAccountService, call: nil) }
  let(:unknown_uris) { Array.new(50) { |index| "https://stranger.test/users/#{index}" } }

  before do
    Setting.chat_enabled = true
    Setting.chat_federation_enabled = true
    local.user.settings[:chat_allow_group_invites] = true
    local.user.save!
    room
    allow(ActivityPub::FetchRemoteAccountService).to receive(:new).and_return(fetcher)
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_federation_enabled = false
  end

  def member_uris(*extra)
    [owner.uri, ActivityPub::TagManager.instance.uri_for(local), *extra]
  end

  it 'fetches nobody for a member list older than what is on record' do
    Sharlayan::ChatFederation::Roster.advance(room, known, 1.minute.from_now)

    service.apply_roster(room, member_uris: member_uris(*unknown_uris), roster_at: Time.current)

    expect(fetcher).to_not have_received(:call)
  end

  it 'still applies an older list to accounts it says nothing newer about' do
    Sharlayan::ChatFederation::Roster.advance(room, owner, 1.minute.from_now)

    service.apply_roster(room, member_uris: member_uris(known.uri, *unknown_uris), roster_at: Time.current)

    expect(room.memberships.exists?(account: known)).to be(true)
    expect(fetcher).to_not have_received(:call)
  end

  it 'limits how many unknown accounts one member list fetches' do
    service.apply_roster(room, member_uris: member_uris(*unknown_uris), roster_at: 1.minute.from_now)

    expect(fetcher).to have_received(:call).exactly(described_class::MAX_ROSTER_ACCOUNT_FETCHES).times
  end

  it 'fetches nobody once the room cannot take more members' do
    2.times { |index| room.memberships.create!(account: Fabricate(:account, domain: 'member.test', uri: "https://member.test/users/extra#{index}", can_chat: true)) }
    stub_const("#{described_class}::MAX_REMOTE_ROOM_MEMBERS", room.memberships.count)

    service.apply_roster(room, member_uris: member_uris(*unknown_uris.first(2)), roster_at: 1.minute.from_now)

    expect(fetcher).to_not have_received(:call)
  end

  it 'adds an unknown account it could fetch' do
    stranger = Fabricate.build(:account, domain: 'stranger.test', uri: unknown_uris.first, inbox_url: 'https://stranger.test/inbox', can_chat: true)
    allow(fetcher).to receive(:call).with(unknown_uris.first) { stranger.tap(&:save!) }

    service.apply_roster(room, member_uris: member_uris(unknown_uris.first), roster_at: 1.minute.from_now)

    expect(room.memberships.exists?(account: stranger)).to be(true)
  end
end
