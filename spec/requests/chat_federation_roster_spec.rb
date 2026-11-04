# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Chat federation roster ordering' do
  let(:service) { Sharlayan::ChatService.new }
  let(:local) { Fabricate(:user).account }
  let(:owner) { Fabricate(:account, domain: 'owner.test', uri: 'https://owner.test/users/owner', inbox_url: 'https://owner.test/users/owner/inbox', can_chat: true) }
  let(:member) { Fabricate(:account, domain: 'member.test', uri: 'https://member.test/users/member', inbox_url: 'https://member.test/users/member/inbox', can_chat: true) }
  let(:room_uri) { 'https://owner.test/chat/rooms/abc123' }
  let(:room) do
    service.receive_invite(local, owner, room_uri: room_uri, title: 'Remote room').tap { |invitation| service.accept_invitation(local, invitation) }.chat_conversation
  end
  let(:earlier) { 1.minute.from_now.utc.iso8601(3) }
  let(:later) { 2.minutes.from_now.utc.iso8601(3) }
  let(:latest) { 3.minutes.from_now.utc.iso8601(3) }

  before do
    Setting.chat_enabled = true
    Setting.chat_federation_enabled = true
    local.user.settings[:chat_allow_group_invites] = true
    local.user.save!
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_federation_enabled = false
  end

  def perform(json, actor)
    ActivityPub::Activity.factory({ '@context' => 'https://www.w3.org/ns/activitystreams', 'actor' => actor.uri }.merge(json), actor).perform
  end

  def actor_uri(account)
    ActivityPub::TagManager.instance.uri_for(account)
  end

  def add(account, published: nil, **extra)
    { 'id' => "#{room_uri}#add/#{SecureRandom.hex(4)}", 'type' => 'Add', 'target' => room_uri, 'object' => actor_uri(account), 'published' => published }.merge(extra.stringify_keys).compact
  end

  def remove(account, published: nil, **extra)
    { 'id' => "#{room_uri}#remove/#{SecureRandom.hex(4)}", 'type' => 'Remove', 'target' => room_uri, 'object' => actor_uri(account), 'published' => published }.merge(extra.stringify_keys).compact
  end

  def invite(invitee, published: nil)
    {
      'id' => "#{room_uri}#invite/#{SecureRandom.hex(4)}", 'type' => 'Invite', 'target' => ActivityPub::TagManager.instance.uri_for(invitee), 'published' => published,
      'object' => { 'id' => room_uri, 'type' => 'Group', 'name' => 'Remote room', 'attributedTo' => owner.uri }
    }.compact
  end

  def undo_invite(invitee, published: nil)
    {
      'id' => "#{room_uri}#cancel/#{SecureRandom.hex(4)}", 'type' => 'Undo', 'published' => published,
      'object' => { 'type' => 'Invite', 'actor' => owner.uri, 'target' => ActivityPub::TagManager.instance.uri_for(invitee), 'object' => room_uri }
    }.compact
  end

  def member?(account)
    room.memberships.exists?(account: account)
  end

  describe 'outgoing timestamps' do
    let(:owned) { service.create_conversation(local, type: :group, title: 'Room') }
    let(:invitation) { owned.invitations.create!(inviter_account: local, invitee_account: member) }

    it 'stamps roster activities with milliseconds' do
      payloads = {
        add: Sharlayan::ChatFederation::Payload.add(owned, member),
        remove: Sharlayan::ChatFederation::Payload.remove(owned, member),
        invite: Sharlayan::ChatFederation::Payload.invite(owned, member),
        cancel: Sharlayan::ChatFederation::Payload.cancel(invitation),
        accept: Sharlayan::ChatFederation::Payload.accept(invitation),
        reject: Sharlayan::ChatFederation::Payload.reject(invitation),
        reject_invite: Sharlayan::ChatFederation::Payload.reject_invite(member, local, room_uri),
      }

      expect(payloads.transform_values { |payload| payload['published'] }).to all(satisfy { |_, published| published.match?(/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z\z/) })
    end
  end

  describe 'Add and Remove' do
    before { room }

    it 'ignores an Add older than a Remove that overtook it' do
      perform(remove(member, published: later), member)
      perform(add(member, published: earlier), owner)

      expect(member?(member)).to be(false)
    end

    it 'ignores a Remove older than the Add that overtook it' do
      perform(add(member, published: later), owner)
      perform(remove(member, published: earlier), owner)

      expect(member?(member)).to be(true)
    end

    it 'lets a Remove win over an Add with the same time' do
      perform(add(member, published: earlier), owner)
      perform(remove(member, published: earlier), owner)

      expect(member?(member)).to be(false)
    end

    it 'does not let an Add with the same time undo a Remove' do
      perform(remove(member, published: earlier), owner)
      perform(add(member, published: earlier), owner)

      expect(member?(member)).to be(false)
    end

    it 'applies newer events in order' do
      perform(add(member, published: earlier), owner)
      perform(remove(member, published: later), owner)
      perform(add(member, published: latest), owner)

      expect(member?(member)).to be(true)
    end

    it 'applies activities without a time in arrival order' do
      perform(add(member, published: later), owner)
      perform(remove(member), owner)
      expect(member?(member)).to be(false)

      perform(add(member), owner)
      expect(member?(member)).to be(true)
    end

    it 'remembers the order after the membership is gone and forgets it with the room' do
      perform(add(member, published: earlier), owner)
      perform(remove(member, published: later), owner)

      expect(ChatRosterState.find_by(chat_conversation: room, account: member).last_roster_at).to eq(Time.iso8601(later))

      service.receive_room_delete(owner, room_uri: room_uri)

      expect(ChatRosterState.where(chat_conversation_id: room.id)).to be_empty
    end

    it 'learns of an unknown account from the owner so a late Add stays ignored' do
      stranger_uri = 'https://member.test/users/unknown'
      stub_request(:get, stranger_uri).to_return(status: 404)

      expect { perform({ 'id' => "#{room_uri}#remove/1", 'type' => 'Remove', 'target' => room_uri, 'object' => stranger_uri, 'published' => later }, owner) }.to_not raise_error
      expect(a_request(:get, stranger_uri)).to have_been_made.at_least_once
    end

    it 'does not look up an unknown account named by anyone but the owner' do
      stranger_uri = 'https://member.test/users/unknown'
      stub_request(:get, stranger_uri).to_return(status: 404)

      perform({ 'id' => "#{room_uri}#remove/1", 'type' => 'Remove', 'target' => room_uri, 'object' => stranger_uri, 'published' => later }, member)

      expect(a_request(:get, stranger_uri)).to_not have_been_made
    end
  end

  describe 'Invite and acceptance' do
    before { room }

    it 'raises the order to the Invite so an earlier Remove arriving late cannot undo a re-invitation' do
      perform(invite(local, published: later), owner)
      perform(remove(local, published: earlier), owner)

      expect(member?(local)).to be(true)
    end

    it 'keeps a later Remove working after an Invite' do
      perform(invite(local, published: later), owner)
      perform(remove(local, published: latest), owner)

      expect(member?(local)).to be(false)
    end

    it 'always sends Accept even when an old membership is still mirrored' do
      invitation = room.invitations.create!(inviter_account: owner, invitee_account: local)

      Sidekiq::Testing.fake! do
        ActivityPub::DeliveryWorker.clear
        service.accept_invitation(local, invitation)

        accepts = ActivityPub::DeliveryWorker.jobs.select { |job| JSON.parse(job['args'][0])['type'] == 'Accept' }
        expect(accepts.size).to eq(1)
        expect(accepts.first['args'][2]).to eq(owner.inbox_url)
      end
    end

    it 'answers an Invite for a mirrored member with Accept and survives the late Remove' do
      Sidekiq::Testing.fake! do
        ActivityPub::DeliveryWorker.clear
        perform(invite(local, published: later), owner)
        perform(remove(local, published: earlier), owner)

        expect(ActivityPub::DeliveryWorker.jobs.map { |job| JSON.parse(job['args'][0])['type'] }).to include('Accept')
      end
      expect(member?(local)).to be(true)
    end
  end

  describe 'on the room owner' do
    let(:owned) { service.create_conversation(local, type: :group, title: 'Room') }

    def accept_json(actor, published: nil)
      {
        'id' => "#{owned.uri}#accept/#{SecureRandom.hex(4)}", 'type' => 'Accept', 'published' => published,
        'object' => { 'type' => 'Invite', 'actor' => ActivityPub::TagManager.instance.uri_for(local), 'target' => actor.uri, 'object' => owned.uri }
      }.compact
    end

    it 'ignores a departure sent before a re-acceptance' do
      owned.invitations.create!(inviter_account: local, invitee_account: member)
      perform(accept_json(member, published: latest), member)

      perform({ 'id' => "#{owned.uri}#remove/1", 'type' => 'Remove', 'target' => owned.uri, 'object' => member.uri, 'published' => later }, member)

      expect(owned.memberships.exists?(account: member)).to be(true)
    end

    it 'says nothing to an account that was never invited' do
      Sidekiq::Testing.fake! do
        owned
        ActivityPub::DeliveryWorker.clear
        perform(accept_json(member, published: earlier), member)

        expect(ActivityPub::DeliveryWorker.jobs).to be_empty
      end
      expect(owned.memberships.exists?(account: member)).to be(false)
    end

    it 'does not spend retries on a message from an account with neither an invitation nor a membership' do
      owned

      expect { service.receive_group_message(member, room_uri: owned.uri, uri: 'https://member.test/chat/messages/1', text: 'hi') }
        .to raise_error(Sharlayan::ChatService::Forbidden)
    end

    it 'keeps waiting when the sender has a pending invitation whose Accept may be on the way' do
      owned.invitations.create!(inviter_account: local, invitee_account: member)

      expect { service.receive_group_message(member, room_uri: owned.uri, uri: 'https://member.test/chat/messages/1', text: 'hi') }
        .to raise_error(Sharlayan::ChatFederation::DependencyNotReadyError)
    end

    it 'never publishes the room members to invitees' do
      invitation = owned.invitations.create!(inviter_account: local, invitee_account: member)
      documents = [
        Sharlayan::ChatFederation::Payload.invite(owned, member),
        Sharlayan::ChatFederation::Payload.accept(invitation),
        Sharlayan::ChatFederation::Payload.update_room(owned),
        Sharlayan::ChatFederation::Payload.delete_room(owned),
      ]

      expect(documents.map { |document| document.except('@context').to_json }).to all(satisfy { |json| !json.include?('_misskey_chatRoomMembers') && !json.include?(member.uri.sub('member', 'other')) })
      expect(documents.values_at(2, 3).flat_map(&:keys)).to_not include('to', 'cc')
    end
  end

  describe 'every way of becoming a group member' do
    def roster_time(conversation, account)
      ChatRosterState.find_by(chat_conversation: conversation, account: account)&.last_roster_at
    end

    it 'records the owner of a new room' do
      owned = service.create_conversation(local, type: :group, title: 'Room')

      expect(roster_time(owned, local)).to be_within(1.minute).of(Time.current)
    end

    it 'records the owner when a room is mirrored' do
      expect(roster_time(room, owner)).to be_within(1.minute).of(Time.current)
    end

    it 'records a local account accepting an invitation to a room owned elsewhere' do
      expect(roster_time(room, local)).to be_within(1.minute).of(Time.current)
    end

    it 'moves past the time of the Invite when a local account accepts' do
      invitation = service.receive_invite(local, owner, room_uri: room_uri, title: 'Remote room', published: 1.hour.ago)
      service.accept_invitation(local, invitation)

      expect(roster_time(invitation.chat_conversation, local)).to be_within(1.minute).of(Time.current)
    end

    it 'records a local account accepting an invitation to a room owned here' do
      invitee = Fabricate(:user).account
      owned = service.create_conversation(local, type: :group, title: 'Room')
      service.accept_invitation(invitee, owned.invitations.create!(inviter_account: local, invitee_account: invitee))

      expect(roster_time(owned, invitee)).to be_within(1.minute).of(Time.current)
    end

    it 'records a remote account accepting, with the time it states' do
      owned = service.create_conversation(local, type: :group, title: 'Room')
      owned.invitations.create!(inviter_account: local, invitee_account: member)
      service.receive_accept(member, room_uri: owned.uri, published: Time.iso8601(earlier))

      expect(roster_time(owned, member)).to eq(Time.iso8601(earlier))
    end

    it 'records a remote account accepting from a server that states no time' do
      owned = service.create_conversation(local, type: :group, title: 'Room')
      owned.invitations.create!(inviter_account: local, invitee_account: member)
      service.receive_accept(member, room_uri: owned.uri)

      expect(roster_time(owned, member)).to be_within(1.minute).of(Time.current)
    end

    it 'records an Add with the time it states' do
      room
      perform(add(member, published: earlier), owner)

      expect(roster_time(room, member)).to eq(Time.iso8601(earlier))
    end

    it 'records an Add from a server that states no time' do
      room
      perform(add(member), owner)

      expect(roster_time(room, member)).to be_within(1.minute).of(Time.current)
    end

    it 'records a member the owner list adds, with the time of the list' do
      service.apply_roster(room, member_uris: [owner.uri, actor_uri(local), member.uri], roster_at: Time.iso8601(earlier))

      expect(roster_time(room, member)).to eq(Time.iso8601(earlier))
    end

    it 'records any membership created directly' do
      room.memberships.create!(account: member)

      expect(roster_time(room, member)).to be_within(1.minute).of(Time.current)
    end

    it 'keeps no record for a direct conversation, which has no member list' do
      direct = ChatConversation.create!(conversation_type: :direct, direct_key: [local.id, member.id].sort.join(':'))
      direct.memberships.create!([{ account: local }, { account: member }])

      expect(ChatRosterState.where(chat_conversation: direct)).to be_empty
    end
  end

  describe 'Undo(Invite) for a membership' do
    before { room }

    it 'removes the membership when the cancellation is newer' do
      perform(invite(local, published: earlier), owner)
      perform(undo_invite(local, published: later), owner)

      expect(ChatMembership.where(account: local, chat_conversation_id: room.id)).to be_empty
    end

    it 'ignores a cancellation that arrives after a re-invitation was accepted' do
      perform(invite(local, published: latest), owner)
      perform(undo_invite(local, published: later), owner)

      expect(member?(local)).to be(true)
    end

    it 'keeps the membership when a cancellation has no time to show it is newer' do
      perform(undo_invite(local), owner)

      expect(member?(local)).to be(true)
    end
  end

  describe 'remote times' do
    before { room }

    it 'treats a far future time as not stated' do
      perform(add(member, published: 1.hour.from_now.iso8601(3)), owner)

      expect(member?(member)).to be(true)
      expect(ChatRosterState.find_by(chat_conversation: room, account: member).last_roster_at).to be_within(1.minute).of(Time.current)

      perform(remove(member, published: 1.minute.from_now.iso8601(3)), owner)
      expect(member?(member)).to be(false)
    end

    it 'accepts a time within the allowed clock skew' do
      published = 4.minutes.from_now.iso8601(3)
      perform(add(member, published: published), owner)

      expect(ChatRosterState.find_by(chat_conversation: room, account: member).last_roster_at).to eq(Time.iso8601(published))
    end

    it 'does not let a far future room state freeze later changes' do
      perform({ 'id' => "#{room_uri}#update/1", 'type' => 'Update', 'object' => { 'id' => room_uri, 'type' => 'Group', 'name' => 'future', 'updated' => 1.day.from_now.iso8601(3), 'attributedTo' => owner.uri } }, owner)
      perform({ 'id' => "#{room_uri}#update/2", 'type' => 'Update', 'object' => { 'id' => room_uri, 'type' => 'Group', 'name' => 'present', 'updated' => Time.current.iso8601(3), 'attributedTo' => owner.uri } }, owner)

      expect(room.reload.title).to eq('present')
    end

    it 'does not let a far future edit freeze a message' do
      room.memberships.create!(account: member)
      uri = 'https://member.test/chat/messages/1'
      note = { 'id' => uri, 'type' => 'Note', 'attributedTo' => member.uri, '_misskey_talk' => true, '_misskey_chatRoom' => room_uri, '_misskey_content' => 'one' }

      perform({ 'id' => "#{uri}/activity", 'type' => 'Create', 'object' => note }, member)
      perform({ 'id' => "#{uri}#update/1", 'type' => 'Update', 'object' => note.merge('_misskey_content' => 'future', 'updated' => 1.day.from_now.iso8601(3)) }, member)
      perform({ 'id' => "#{uri}#update/2", 'type' => 'Update', 'object' => note.merge('_misskey_content' => 'present', 'updated' => 1.minute.from_now.iso8601(3)) }, member)

      expect(ChatMessage.find_by!(uri: uri).text).to eq('present')
    end
  end

  describe 'a deleted room' do
    let(:message_uri) { 'https://member.test/chat/messages/1' }
    let(:note) { { 'id' => message_uri, 'type' => 'Note', 'attributedTo' => member.uri, '_misskey_talk' => true, '_misskey_chatRoom' => room_uri, '_misskey_content' => 'late' } }

    before do
      room.memberships.create!(account: member)
      service.receive_group_message(member, room_uri: room_uri, uri: message_uri, text: 'stored')
      perform({ 'id' => "#{room_uri}#delete", 'type' => 'Delete', 'object' => { 'id' => room_uri, 'type' => 'Tombstone', 'formerType' => 'Group' } }, owner)
    end

    it 'records the room and when it was deleted for at least 30 days' do
      expect(service.room_deleted_at(room_uri)).to be_within(1.minute).of(Time.current)
      expect(service.redis.ttl(Sharlayan::ChatService.room_tombstone_key(room_uri))).to be >= 30.days.to_i - 60
    end

    it 'skips a late message without retrying' do
      expect { perform({ 'id' => "#{message_uri}/activity", 'type' => 'Create', 'object' => note }, member) }.to_not raise_error
      expect(ChatMessage.exists?(uri: message_uri)).to be(false)
    end

    it 'skips a late relayed message without retrying' do
      announce = { 'id' => "#{room_uri}#relay/x", 'type' => 'Announce', 'object' => message_uri, 'context' => room_uri, '_misskey_chatRoom' => room_uri }

      expect { perform(announce, owner) }.to_not raise_error
    end

    it 'skips a late room update and invitation' do
      expect { perform({ 'id' => "#{room_uri}#update/1", 'type' => 'Update', 'object' => { 'id' => room_uri, 'type' => 'Group', 'name' => 'late', 'attributedTo' => owner.uri } }, owner) }.to_not raise_error
      expect { perform(invite(local, published: earlier), owner) }.to not_change(ChatConversation, :count)
    end

    it 'skips a late reaction to a message of that room without retrying' do
      reaction = { 'id' => 'https://member.test/chat-reactions/1', 'type' => 'EmojiReact', 'object' => message_uri, 'content' => '👍' }

      expect { perform(reaction, member) }.to_not raise_error
      expect { perform({ 'id' => "#{reaction['id']}/undo", 'type' => 'Undo', 'object' => reaction }, member) }.to_not raise_error
    end

    it 'records the room when its owner removes themselves' do
      other_uri = 'https://owner.test/chat/rooms/other'
      other = service.receive_invite(local, owner, room_uri: other_uri, title: 'Other').tap { |invitation| service.accept_invitation(local, invitation) }.chat_conversation

      perform({ 'id' => "#{other_uri}#remove/1", 'type' => 'Remove', 'target' => other_uri, 'object' => owner.uri }, owner)

      expect(ChatConversation.exists?(other.id)).to be(false)
      expect(service.room_deleted_at(other_uri)).to be_present
    end
  end

  describe 'a Note with only HTML content' do
    let(:uri) { 'https://member.test/chat/messages/html' }

    def received_text(content)
      perform({ 'id' => "#{uri}/activity", 'type' => 'Create', 'object' => { 'id' => uri, 'type' => 'Note', 'attributedTo' => member.uri, '_misskey_talk' => true, 'content' => content, 'to' => [ActivityPub::TagManager.instance.uri_for(local)] } }, member)
      ChatMessage.find_by!(uri: uri).text
    end

    before do
      local.user.settings[:chat_policy] = 'everyone'
      local.user.save!
    end

    it 'keeps line breaks and paragraphs' do
      expect(received_text('<p>one<br>two<br />three</p><p>four &amp; five</p>')).to eq("one\ntwo\nthree\n\nfour & five")
    end

    it 'still drops other markup' do
      expect(received_text('<p><b>bold</b> <a href="https://example.com">link</a></p>')).to eq('bold link')
    end
  end
end
