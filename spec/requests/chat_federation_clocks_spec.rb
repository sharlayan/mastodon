# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Chat federation across servers with different clocks' do
  let(:service) { Sharlayan::ChatService.new }
  let(:local) { Fabricate(:user).account }
  let(:owner) { Fabricate(:account, domain: 'owner.test', uri: 'https://owner.test/users/owner', inbox_url: 'https://owner.test/users/owner/inbox', can_chat: true) }
  let(:member) { Fabricate(:account, domain: 'member.test', uri: 'https://member.test/users/member', inbox_url: 'https://member.test/users/member/inbox', can_chat: true) }
  let(:third) { Fabricate(:account, domain: 'third.test', uri: 'https://third.test/users/third', inbox_url: 'https://third.test/users/third/inbox', can_chat: true) }
  let(:room_uri) { 'https://owner.test/chat/rooms/abc123' }
  let(:message_uri) { 'https://member.test/chat/messages/m1' }

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

  def actor_uri(account)
    ActivityPub::TagManager.instance.uri_for(account)
  end

  def perform(json, actor)
    ActivityPub::Activity.factory({ '@context' => 'https://www.w3.org/ns/activitystreams', 'actor' => actor.uri }.merge(json), actor).perform
  end

  def stamp(time)
    time&.utc&.iso8601(3)
  end

  def invite_json(invitee, at: nil, uri: room_uri)
    { 'id' => "#{uri}#invite/#{SecureRandom.hex(4)}", 'type' => 'Invite', 'target' => actor_uri(invitee), 'published' => stamp(at),
      'object' => { 'id' => uri, 'type' => 'Group', 'name' => 'Remote room', 'attributedTo' => owner.uri } }.compact
  end

  def undo_invite_json(invitee, at: nil)
    { 'id' => "#{room_uri}#cancel/#{SecureRandom.hex(4)}", 'type' => 'Undo', 'published' => stamp(at),
      'object' => { 'type' => 'Invite', 'actor' => owner.uri, 'target' => actor_uri(invitee), 'object' => room_uri } }.compact
  end

  def add_json(account, at: nil, uri: room_uri)
    { 'id' => "#{uri}#add/#{SecureRandom.hex(4)}", 'type' => 'Add', 'target' => uri, 'object' => actor_uri(account), 'published' => stamp(at) }.compact
  end

  def remove_json(account, at: nil, uri: room_uri)
    { 'id' => "#{uri}#remove/#{SecureRandom.hex(4)}", 'type' => 'Remove', 'target' => uri, 'object' => actor_uri(account), 'published' => stamp(at) }.compact
  end

  def mirror
    ChatConversation.find_by(uri: room_uri)
  end

  def member?(account)
    mirror&.memberships&.exists?(account: account) || false
  end

  def pending?(account)
    mirror&.invitations&.pending&.exists?(invitee_account: account) || false
  end

  def roster_time(conversation, account)
    ChatRosterState.find_by(chat_conversation: conversation, account: account)&.last_roster_at
  end

  describe 'a member server, comparing what the owner sends by the owner clock' do
    let(:behind) { 1.hour.ago }

    before do
      perform(invite_json(local, at: behind), owner)
      service.accept_invitation(local, mirror.invitations.find_by!(invitee_account: local))
    end

    it 'does not let its own clock into the record when someone here accepts' do
      expect(roster_time(mirror, local)).to eq(Time.iso8601(stamp(behind)))
    end

    it 'applies a removal the owner stamped just after the invitation' do
      perform(remove_json(local, at: behind + 1.second), owner)

      expect(member?(local)).to be(false)
    end

    it 'applies a cancellation that crossed the acceptance' do
      perform(undo_invite_json(local, at: behind + 1.second), owner)

      expect(member?(local)).to be(false)
    end

    it 'ignores a cancellation older than the invitation' do
      perform(undo_invite_json(local, at: behind - 1.second), owner)

      expect(member?(local)).to be(true)
    end

    it 'applies a member list the owner made just after the invitation, once the acceptance has had time to arrive' do
      mirror.invitations.find_by!(invitee_account: local).update!(updated_at: 1.hour.ago)
      second = Fabricate(:user).account
      second.user.settings[:chat_allow_group_invites] = true
      second.user.save!
      perform(invite_json(second, at: behind), owner)
      service.accept_invitation(second, mirror.invitations.find_by!(invitee_account: second))
      mirror.invitations.find_by!(invitee_account: second).update!(updated_at: 1.hour.ago)

      service.apply_roster(mirror, member_uris: [owner.uri, actor_uri(second)], roster_at: behind + 1.second)

      expect(member?(local)).to be(false)
      expect(member?(second)).to be(true)
    end
  end

  describe 'a third server, hearing someone leave by their own clock' do
    before do
      perform(invite_json(local, at: Time.current), owner)
      service.accept_invitation(local, mirror.invitations.find_by!(invitee_account: local))
      perform(add_json(member, at: Time.current), owner)
    end

    it 'applies it when their clock is behind the owner' do
      perform(remove_json(member, at: 1.hour.ago), member)

      expect(member?(member)).to be(false)
    end

    it 'does not let a fast clock hold back the next Add from the owner' do
      perform(remove_json(member, at: 4.minutes.from_now), member)
      expect(member?(member)).to be(false)

      perform(add_json(member, at: 1.second.from_now), owner)

      expect(member?(member)).to be(true)
    end

    it 'keeps its record in the owner clock' do
      before = roster_time(mirror, member)

      perform(remove_json(member, at: 4.minutes.from_now), member)

      expect(roster_time(mirror, member)).to eq(before)
    end

    it 'still lets someone who never joined be ignored' do
      expect { perform(remove_json(third, at: Time.current), third) }.to_not(change(ChatRosterState, :count))
    end
  end

  describe 'the owner server, comparing a member departure with the same server' do
    let(:owned) { service.create_conversation(local, type: :group, title: 'Room') }

    def accept_json(actor, at:)
      { 'id' => "#{owned.uri}#accept/#{SecureRandom.hex(4)}", 'type' => 'Accept', 'published' => stamp(at),
        'object' => { 'type' => 'Invite', 'actor' => actor_uri(local), 'target' => actor.uri, 'object' => owned.uri } }
    end

    def leave_json(actor, at:)
      remove_json(actor, at: at, uri: owned.uri)
    end

    def member_of_owned?(account)
      owned.memberships.exists?(account: account)
    end

    before { owned.invitations.create!(inviter_account: local, invitee_account: member) }

    it 'honours a departure right after re-accepting from a server an hour behind' do
      accepted = 1.hour.ago
      perform(accept_json(member, at: accepted), member)
      expect(roster_time(owned, member)).to eq(Time.iso8601(stamp(accepted)))

      perform(leave_json(member, at: accepted + 1.second), member)

      expect(member_of_owned?(member)).to be(false)
    end

    it 'honours a departure after being kicked and re-invited, whatever time this server keeps' do
      perform(accept_json(member, at: 1.hour.ago), member)
      service.kick(local, owned, member)
      owned.invitations.create!(inviter_account: local, invitee_account: member)
      perform(accept_json(member, at: 59.minutes.ago), member)

      perform(leave_json(member, at: 58.minutes.ago), member)

      expect(member_of_owned?(member)).to be(false)
    end

    it 'still ignores a departure sent before the last acceptance' do
      perform(accept_json(member, at: 1.hour.ago), member)

      perform(leave_json(member, at: 2.hours.ago), member)

      expect(member_of_owned?(member)).to be(true)
    end
  end

  describe 'activities older than the record' do
    let(:early) { 3.minutes.ago }
    let(:middle) { 2.minutes.ago }
    let(:late) { 1.minute.ago }

    it 'ignores an older Invite, which does not bring back a cancelled invitation' do
      perform(invite_json(local, at: middle), owner)
      perform(undo_invite_json(local, at: late), owner)
      expect(pending?(local)).to be(false)

      perform(invite_json(local, at: early), owner)

      expect(pending?(local)).to be(false)
    end

    it 'ignores an older cancellation, which does not end the pending invitation' do
      perform(invite_json(local, at: late), owner)

      perform(undo_invite_json(local, at: early), owner)

      expect(pending?(local)).to be(true)
    end

    it 'applies a newer cancellation of a pending invitation' do
      perform(invite_json(local, at: early), owner)

      perform(undo_invite_json(local, at: late), owner)

      expect(pending?(local)).to be(false)
    end

    it 'applies an Invite and a cancellation without a time in arrival order' do
      perform(invite_json(local), owner)
      expect(pending?(local)).to be(true)

      perform(undo_invite_json(local), owner)

      expect(pending?(local)).to be(false)
    end

    context 'with a Reject on the owner server' do
      let(:owned) { service.create_conversation(local, type: :group, title: 'Room') }
      let(:invitation) { owned.invitations.create!(inviter_account: local, invitee_account: member) }

      def reject_json(at: nil)
        { 'id' => "#{owned.uri}#reject/#{SecureRandom.hex(4)}", 'type' => 'Reject', 'published' => stamp(at),
          'object' => { 'type' => 'Invite', 'actor' => actor_uri(local), 'target' => member.uri, 'object' => owned.uri } }.compact
      end

      before do
        owned.invitations.create!(inviter_account: local, invitee_account: member)
        service.receive_accept(member, room_uri: owned.uri, published: middle)
        service.kick(local, owned, member)
        invitation
      end

      it 'ignores one older than the last it heard from that server' do
        perform(reject_json(at: early), member)

        expect(invitation.reload).to be_pending
      end

      it 'applies a newer one' do
        perform(reject_json(at: late), member)

        expect(invitation.reload).to be_rejected
      end

      it 'applies one without a time in arrival order' do
        perform(reject_json, member)

        expect(invitation.reload).to be_rejected
      end
    end
  end

  describe 'a relay that arrives before the message' do
    let(:room) do
      service.receive_invite(local, owner, room_uri: room_uri, title: 'Remote room').tap { |invitation| service.accept_invitation(local, invitation) }.chat_conversation
    end
    let(:other_room_uri) { 'https://owner.test/chat/rooms/other' }
    let(:reaction) { { 'id' => 'https://third.test/chat-reactions/1', 'type' => 'EmojiReact', 'actor' => third.uri, 'object' => message_uri, 'content' => '👍', '_misskey_reaction' => '👍' } }

    around { |example| Sidekiq::Testing.fake! { example.run } }

    before do
      room.memberships.create!(account: member)
      room.memberships.create!(account: third)
      ActivityPub::ProcessingWorker.clear
    end

    def announce(object, room: room_uri, id: "#{room}#relay/#{SecureRandom.hex(4)}")
      perform({ 'id' => id, 'type' => 'Announce', 'object' => object, 'context' => room, '_misskey_chatRoom' => room }, owner)
    end

    def note(uri: message_uri, room: room_uri)
      { 'id' => "#{uri}/activity", 'type' => 'Create', 'object' => { 'id' => uri, 'type' => 'Note', 'attributedTo' => member.uri, '_misskey_talk' => true, '_misskey_content' => 'hello', '_misskey_chatRoom' => room } }
    end

    def run_released_jobs
      jobs = ActivityPub::ProcessingWorker.jobs.dup
      ActivityPub::ProcessingWorker.clear
      jobs.each { |job| ActivityPub::ProcessingWorker.new.perform(*job['args']) }
    end

    it 'holds a reaction without using up retries and applies it when the message arrives' do
      expect { announce(reaction) }.to_not raise_error
      expect(ActivityPub::ProcessingWorker.jobs).to be_empty

      perform(note, member)
      run_released_jobs

      expect(ChatMessage.find_by!(uri: message_uri).reactions.pluck(:account_id, :reaction)).to eq([[third.id, '👍']])
    end

    it 'keeps what it holds for six hours' do
      announce(reaction)

      expect(service.redis.ttl(Sharlayan::ChatService.held_relay_key(message_uri))).to be_between(6.hours.to_i - 60, 6.hours.to_i)
    end

    it 'applies a held reaction and its held Undo in order' do
      announce(reaction)
      announce({ 'id' => "#{reaction['id']}/undo", 'type' => 'Undo', 'actor' => third.uri, 'object' => reaction })

      perform(note, member)
      run_released_jobs

      expect(ChatMessage.find_by!(uri: message_uri).reactions).to be_empty
    end

    it 'does not apply a held reaction to a message of another room' do
      other = service.receive_invite(local, owner, room_uri: other_room_uri, title: 'Other').tap { |invitation| service.accept_invitation(local, invitation) }.chat_conversation
      other.memberships.create!(account: member)
      other.memberships.create!(account: third)
      announce(reaction)

      perform(note(room: other_room_uri), member)
      run_released_jobs

      expect(ChatMessage.find_by!(uri: message_uri).chat_conversation).to eq(other)
      expect(ChatMessage.find_by!(uri: message_uri).reactions).to be_empty
    end

    it 'limits what a room can hold' do
      stub_const('Sharlayan::ChatService::MAX_HELD_RELAYS', 1)

      announce(reaction)
      announce(reaction.merge('id' => 'https://third.test/chat-reactions/2', 'object' => 'https://member.test/chat/messages/m2'))

      expect(service.redis.exists?(Sharlayan::ChatService.held_relay_key(message_uri))).to be(true)
      expect(service.redis.exists?(Sharlayan::ChatService.held_relay_key('https://member.test/chat/messages/m2'))).to be(false)
    end

    it 'skips a relayed deletion with no target and leaves it to the direct one' do
      delete = { 'id' => "#{message_uri}#delete", 'type' => 'Delete', 'actor' => member.uri, 'object' => { 'id' => message_uri, 'type' => 'Tombstone' } }

      expect { announce(delete) }.to_not raise_error

      expect(service).to_not be_tombstone(message_uri, member)
      perform(note, member)
      expect(ChatMessage.find_by!(uri: message_uri)).to_not be_deleted
    end
  end

  describe 'the custom emoji of a relayed reaction' do
    let(:room) do
      service.receive_invite(local, owner, room_uri: room_uri, title: 'Remote room').tap { |invitation| service.accept_invitation(local, invitation) }.chat_conversation
    end
    let(:stored) { service.receive_group_message(member, room_uri: room_uri, uri: message_uri, text: 'stored') }
    let(:reaction) { { 'id' => 'https://third.test/chat-reactions/1', 'type' => 'EmojiReact', 'actor' => third.uri, 'object' => message_uri, 'content' => ':wave:', '_misskey_reaction' => ':wave:' } }

    before do
      room.memberships.create!(account: member)
      room.memberships.create!(account: third)
      stored
    end

    def announce(object)
      perform({ 'id' => "#{room_uri}#relay/x", 'type' => 'Announce', 'object' => object, 'context' => room_uri, '_misskey_chatRoom' => room_uri }, owner)
    end

    def emoji_tag(name)
      { 'id' => "https://third.test/emojis/#{name}", 'type' => 'Emoji', 'name' => ":#{name}:", 'icon' => { 'type' => 'Image', 'url' => 'https://owner.test/forged.png' } }
    end

    def stub_emoji(name)
      json = { '@context' => 'https://www.w3.org/ns/activitystreams', 'id' => "https://third.test/emojis/#{name}", 'type' => 'Emoji', 'name' => ":#{name}:", 'icon' => { 'type' => 'Image', 'url' => "https://third.test/emoji/#{name}.png" } }
      stub_request(:get, json['id']).to_return(status: 200, body: json.to_json, headers: { 'Content-Type' => 'application/activity+json' })
      stub_request(:get, "https://third.test/emoji/#{name}.png").to_return(request_fixture('avatar.txt'))
    end

    it 'takes the tag named like the reaction, wherever it is in the list' do
      stub_emoji('wave')
      other = stub_request(:get, 'https://third.test/emojis/other')

      announce(reaction.merge('tag' => [emoji_tag('other'), emoji_tag('wave')]))

      expect(CustomEmoji.find_by(shortcode: 'wave', domain: third.domain).image_remote_url).to eq('https://third.test/emoji/wave.png')
      expect(other).to_not have_been_requested
    end

    it 'fetches nothing when no tag is named like the reaction' do
      other = stub_request(:get, 'https://third.test/emojis/other')

      announce(reaction.merge('tag' => [emoji_tag('other')]))

      expect(other).to_not have_been_requested
      expect(CustomEmoji.find_by(shortcode: 'other', domain: third.domain)).to be_nil
    end
  end

  describe 'a copy of a room a moderator removed here' do
    let(:room) do
      service.receive_invite(local, owner, room_uri: room_uri, title: 'Remote room').tap { |invitation| service.accept_invitation(local, invitation) }.chat_conversation
    end
    let(:invited) { Fabricate(:user).account }

    around { |example| Sidekiq::Testing.fake! { example.run } }

    before do
      room.memberships.create!(account: member)
      invited.user.settings[:chat_allow_group_invites] = true
      invited.user.save!
      room.invitations.create!(inviter_account: owner, invitee_account: invited)
      service.receive_group_message(member, room_uri: room_uri, uri: message_uri, text: 'stored')
      ActivityPub::DeliveryWorker.clear
      service.destroy_conversation_as_admin(room)
    end

    def delivered
      ActivityPub::DeliveryWorker.jobs.map { |job| [JSON.parse(job['args'][0]), job['args'][2]] }
    end

    it 'tells the owner the people here are gone' do
      activities = delivered.select { |_, inbox| inbox == owner.inbox_url }.map(&:first)

      expect(activities.pluck('type')).to contain_exactly('Remove', 'Reject')
      expect(activities.find { |activity| activity['type'] == 'Remove' }).to include('actor' => actor_uri(local), 'object' => actor_uri(local), 'target' => room_uri)
      expect(activities.find { |activity| activity['type'] == 'Reject' }).to include('actor' => actor_uri(invited))
    end

    it 'is told apart from a room its owner deleted' do
      expect(service).to be_room_closed_here(room_uri)
      expect(service).to_not be_room_tombstoned(room_uri)
    end

    it 'skips what arrives later instead of retrying' do
      expect { perform({ 'id' => "#{message_uri}2/activity", 'type' => 'Create', 'object' => { 'id' => "#{message_uri}2", 'type' => 'Note', 'attributedTo' => member.uri, '_misskey_talk' => true, '_misskey_content' => 'late', '_misskey_chatRoom' => room_uri } }, member) }.to_not raise_error
      expect { perform({ 'id' => "#{room_uri}#relay/x", 'type' => 'Announce', 'object' => message_uri, 'context' => room_uri, '_misskey_chatRoom' => room_uri }, owner) }.to_not raise_error
      expect { perform({ 'id' => 'https://member.test/chat-reactions/1', 'type' => 'EmojiReact', 'object' => "#{message_uri}3", 'content' => '👍', 'context' => room_uri, '_misskey_chatRoom' => room_uri }, member) }.to_not raise_error
      expect { perform({ 'id' => 'https://member.test/chat-reactions/2', 'type' => 'EmojiReact', 'object' => message_uri, 'content' => '👍' }, member) }.to_not raise_error
    end

    it 'can be made again by a new Invite, which ends the mark' do
      perform(invite_json(local, at: Time.current), owner)

      expect(mirror).to be_present
      expect(pending?(local)).to be(true)
      expect(service).to_not be_room_closed_here(room_uri)
    end

    it 'does not bring back a room its owner deleted' do
      service.remember_room_tombstone(room_uri, owner)

      perform(invite_json(local, at: Time.current), owner)

      expect(mirror).to be_nil
    end
  end
end
