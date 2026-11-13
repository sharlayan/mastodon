# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VoiceCallRemoteSession do
  let(:host) { Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/host') }
  let(:role) { Fabricate(:user_role, extra_permissions: UserRole::EXTRA_FLAGS[:join_voice_calls]) }
  let(:member) { Fabricate(:user, role:).account }
  let(:mirror) do
    ChatConversation.create!(conversation_type: :group, owner_account: host, title: 'Mirror', uri: 'https://remote.test/chat/rooms/9').tap do |record|
      record.memberships.create!(account: host, role: :owner)
      record.memberships.create!(account: member)
    end
  end
  let(:session) do
    described_class.create!(
      account: member, chat_conversation: mirror, identity: ActivityPub::TagManager.instance.uri_for(member),
      room_name: 'room-9', origin: 'https://remote.test', expires_at: 12.hours.from_now
    )
  end
  let(:query) do
    Rails.root.join('voice_signal', 'src', 'VoiceSignal', 'AllocationResolver.cs').read.match(/private const string RemoteQuery = """\n(.*?)\n        """;/m)[1]
  end

  before do
    Setting.chat_enabled = true
    Setting.chat_federation_enabled = true
    Setting.voice_call_remote_join_enabled = true
    Setting.voice_call_screen_share_enabled = true
    UserRole.everyone.update!(extra_permissions: 0)
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_federation_enabled = false
    Setting.voice_call_remote_join_enabled = false
    Setting.voice_call_screen_share_enabled = true
  end

  def admitted_origin(identity: session.identity, room_name: session.room_name, can_publish_screen_share: false)
    connection = ActiveRecord::Base.connection
    values = [session.id, identity, room_name, can_publish_screen_share]
    sql = query.gsub(/\$(\d+)/) { connection.quote(values.fetch(Regexp.last_match(1).to_i - 1)) }
    connection.select_value(sql)
  end

  it 'admits current members with a role grant, an everyone grant or administrator permissions' do
    expect(admitted_origin).to eq(session.origin)

    UserRole.everyone.update!(extra_permissions: UserRole::EXTRA_FLAGS[:join_voice_calls])
    member.user.update_column(:role_id, nil)
    expect(admitted_origin).to eq(session.origin)

    UserRole.everyone.update!(extra_permissions: 0)
    role.update!(permissions: UserRole::FLAGS[:administrator], extra_permissions: 0)
    member.user.update_column(:role_id, role.id)
    expect(admitted_origin).to eq(session.origin)
  end

  it 'rechecks the current member and room even if their stored session has not been deleted' do
    expect(admitted_origin).to eq(session.origin)
    mirror.update_column(:archived_at, Time.current)
    expect(admitted_origin).to be_nil

    mirror.update_column(:archived_at, nil)
    mirror.memberships.where(account: member).delete_all
    expect(described_class.exists?(session.id)).to be(true)
    expect(admitted_origin).to be_nil
  end

  it 'rejects nonfunctional local accounts independently of lifecycle callbacks' do
    expect(admitted_origin).to eq(session.origin)
    [
      [member.user, { disabled: true }],
      [member.user, { approved: false }],
      [member.user, { confirmed_at: nil }],
      [member, { suspended_at: Time.current }],
      [member, { requested_deletion_at: Time.current }],
      [member, { memorial: true }],
    ].each do |record, attributes|
      previous = record.attributes.slice(*attributes.keys.map(&:to_s))
      record.update_columns(attributes)
      expect(admitted_origin).to be_nil
      record.update_columns(previous)
      expect(admitted_origin).to eq(session.origin)
    end
  end

  it 'observes edits to effective role permissions and two factor requirements' do
    expect(admitted_origin).to eq(session.origin)
    role.update!(extra_permissions: 0)
    expect(admitted_origin).to be_nil

    UserRole.everyone.update!(extra_permissions: UserRole::EXTRA_FLAGS[:join_voice_calls])
    expect(admitted_origin).to eq(session.origin)
    role.update!(require_2fa: true)
    expect(admitted_origin).to be_nil

    member.user.update_column(:otp_required_for_login, true)
    expect(admitted_origin).to eq(session.origin)
  end

  it 'rejects unavailable or blocked host servers' do
    expect(admitted_origin).to eq(session.origin)
    host.update_column(:suspended_at, Time.current)
    expect(admitted_origin).to be_nil

    host.update_column(:suspended_at, nil)
    host.update_column(:requested_deletion_at, Time.current)
    expect(admitted_origin).to be_nil

    host.update_column(:requested_deletion_at, nil)
    DomainBlock.create!(domain: 'remote.test', severity: :suspend)
    expect(admitted_origin).to be_nil
  end

  it 'rejects existing sessions while any remote chat feature gate is off' do
    expect(admitted_origin).to eq(session.origin)
    %w(chat_enabled chat_federation_enabled voice_call_remote_join_enabled).each do |setting|
      Setting[setting] = false
      expect(admitted_origin).to be_nil
      Setting[setting] = true
      expect(admitted_origin).to eq(session.origin)
    end
  end

  it 'requires the current screen permission only for tokens that can publish screen tracks' do
    expect(admitted_origin).to eq(session.origin)
    expect(admitted_origin(can_publish_screen_share: true)).to be_nil

    role.update!(extra_permissions: UserRole::EXTRA_FLAGS.values_at(:join_voice_calls, :share_screens).reduce(:|))
    expect(admitted_origin(can_publish_screen_share: true)).to eq(session.origin)

    role.update!(extra_permissions: UserRole::EXTRA_FLAGS[:join_voice_calls])
    expect(admitted_origin(can_publish_screen_share: true)).to be_nil
    expect(admitted_origin).to eq(session.origin)
  end

  it 'uses inherited and administrator screen grants while respecting the screen feature gate' do
    UserRole.everyone.update!(extra_permissions: UserRole::EXTRA_FLAGS[:share_screens])
    expect(admitted_origin(can_publish_screen_share: true)).to eq(session.origin)

    UserRole.everyone.update!(extra_permissions: 0)
    expect(admitted_origin(can_publish_screen_share: true)).to be_nil
    role.update!(permissions: UserRole::FLAGS[:administrator])
    expect(admitted_origin(can_publish_screen_share: true)).to eq(session.origin)

    Setting.voice_call_screen_share_enabled = false
    expect(admitted_origin(can_publish_screen_share: true)).to be_nil
    expect(admitted_origin).to eq(session.origin)
  end

  it 'binds each session to its identity, room name and expiry' do
    expect(admitted_origin).to eq(session.origin)
    expect(admitted_origin(identity: 'https://local.test/users/other')).to be_nil
    expect(admitted_origin(room_name: 'room-other')).to be_nil
    session.update_column(:expires_at, 1.second.ago)
    expect(admitted_origin).to be_nil
  end
end
