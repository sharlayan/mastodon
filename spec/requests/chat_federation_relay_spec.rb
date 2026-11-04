# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Chat federation relay and roster sync' do
  let(:service) { Sharlayan::ChatService.new }
  let(:local) { Fabricate(:user).account }
  let(:owner) { Fabricate(:account, domain: 'owner.test', uri: 'https://owner.test/users/owner', inbox_url: 'https://owner.test/users/owner/inbox', can_chat: true) }
  let(:member) { Fabricate(:account, domain: 'member.test', uri: 'https://member.test/users/member', inbox_url: 'https://member.test/users/member/inbox', can_chat: true) }
  let(:third) { Fabricate(:account, domain: 'third.test', uri: 'https://third.test/users/third', inbox_url: 'https://third.test/users/third/inbox', can_chat: true) }
  let(:room_uri) { 'https://owner.test/chat/rooms/abc123' }
  let(:message_uri) { 'https://member.test/chat/messages/m1' }
  let(:room) do
    service.receive_invite(local, owner, room_uri: room_uri, title: 'Remote room').tap { |invitation| service.accept_invitation(local, invitation) }.chat_conversation
  end

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

  def group_json(members:, roster_at:, **extra)
    { '@context' => Sharlayan::ChatFederation::Payload::CONTEXT, 'id' => room_uri, 'type' => 'Group', 'attributedTo' => owner.uri, 'name' => 'Remote room',
      '_misskey_chatRoomMembers' => members, '_misskey_chatRoomRosterAt' => roster_at }.merge(extra.stringify_keys)
  end

  def stub_group(json)
    stub_request(:get, room_uri).to_return(status: 200, body: json.to_json, headers: { 'Content-Type' => 'application/activity+json' })
  end

  def sync_jobs
    ChatRosterSyncWorker.jobs.map { |job| job['args'].first }
  end

  describe 'the Group an owner serves' do
    let(:owned) { service.create_conversation(local, type: :group, title: 'Room') }

    before do
      owned.memberships.create!(account: member)
      owned.invitations.create!(inviter_account: local, invitee_account: third)
    end

    it 'names the members and the time to a member' do
      get "/chat/rooms/#{owned.id}", headers: { 'Accept' => 'application/activity+json' }, sign_with: member

      expect(response.parsed_body['_misskey_chatRoomMembers']).to contain_exactly(actor_uri(local), member.uri)
      expect(response.parsed_body['_misskey_chatRoomRosterAt']).to match(/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z\z/)
    end

    it 'keeps the members from someone who is only invited' do
      get "/chat/rooms/#{owned.id}", headers: { 'Accept' => 'application/activity+json' }, sign_with: third

      expect(response).to have_http_status(200)
      expect(response.parsed_body.keys).to_not include('_misskey_chatRoomMembers', '_misskey_chatRoomRosterAt')
    end
  end

  describe 'asking for the member list' do
    around { |example| Sidekiq::Testing.fake! { example.run } }

    before do
      room
      ChatRosterSyncWorker.clear
    end

    it 'asks when an unlisted account fetches a message of a room owned elsewhere, and still answers 404' do
      message = room.messages.create!(account: local, text: 'hello')
      message.update!(uri: "https://cb6e6126.ngrok.io/chat/messages/#{message.id}")

      get "/chat/messages/#{message.id}", headers: { 'Accept' => 'application/activity+json' }, sign_with: member

      expect(response).to have_http_status(404)
      expect(sync_jobs).to eq([room.id])
    end

    it 'does not ask for a room owned here' do
      owned = service.create_conversation(local, type: :group, title: 'Room')
      message = owned.messages.create!(account: local, text: 'hello')

      get "/chat/messages/#{message.id}", headers: { 'Accept' => 'application/activity+json' }, sign_with: member

      expect(response).to have_http_status(404)
      expect(sync_jobs).to be_empty
    end

    it 'asks when an unlisted account sends a message and keeps the activity retrying' do
      expect { service.receive_group_message(member, room_uri: room_uri, uri: message_uri, text: 'hi') }
        .to raise_error(Sharlayan::ChatFederation::DependencyNotReadyError)

      expect(sync_jobs).to eq([room.id])
    end

    it 'asks when an unlisted account edits a message and keeps the activity retrying' do
      room.memberships.create!(account: member)
      message = service.receive_group_message(member, room_uri: room_uri, uri: message_uri, text: 'hi')
      room.memberships.find_by!(account: member).destroy!
      ChatRosterSyncWorker.clear

      expect { service.update_remote_message(member, message, text: 'edited', edited_at: Time.current) }
        .to raise_error(Sharlayan::ChatFederation::DependencyNotReadyError)

      expect(sync_jobs).to eq([room.id])
    end

    it 'asks when an unlisted account reacts and keeps the activity retrying' do
      third_message = room.messages.create!(account: local, text: 'hello', uri: 'https://cb6e6126.ngrok.io/chat/messages/1')

      expect { perform({ 'id' => 'https://member.test/chat-reactions/1', 'type' => 'EmojiReact', 'object' => third_message.uri, 'content' => '👍' }, member) }
        .to raise_error(Sharlayan::ChatFederation::DependencyNotReadyError)

      expect(sync_jobs).to eq([room.id])
    end

    it 'asks once a minute for each room and member' do
      2.times { Sharlayan::ChatFederation::Roster.request_sync(room, member.id) }
      expect(sync_jobs.size).to eq(1)

      Sharlayan::ChatFederation::Roster.request_sync(room, third.id)
      expect(sync_jobs.size).to eq(2)
    end

    it 'keeps the limit for a minute' do
      Sharlayan::ChatFederation::Roster.request_sync(room, member.id)

      expect(service.redis.ttl("chat_roster_sync:#{room.id}:#{member.id}")).to be_between(55, 60)
    end
  end

  describe 'applying the member list' do
    let(:roster_at) { '2026-11-03T00:00:10.000Z' }
    let(:older) { '2026-11-03T00:00:05.000Z' }
    let(:newer) { '2026-11-03T00:00:15.000Z' }

    def sync(members: [owner.uri, actor_uri(local)], at: roster_at, **extra)
      stub_group(group_json(members: members, roster_at: at, **extra))
      Sharlayan::ChatFederation::Roster.sync(room)
    end

    before { room }

    it 'adds a member this server never heard of so a retried message succeeds' do
      sync(members: [owner.uri, actor_uri(local), member.uri])

      expect(room.memberships.exists?(account: member)).to be(true)
      expect(service.receive_group_message(member, room_uri: room_uri, uri: message_uri, text: 'hi').text).to eq('hi')
    end

    it 'signs the request as a local member' do
      sync(members: [owner.uri, actor_uri(local), member.uri])

      expect(a_request(:get, room_uri).with { |request| request.headers['Signature'].to_s.include?(ActivityPub::TagManager.instance.key_uri_for(local)) }).to have_been_made
    end

    it 'looks up an account it does not know' do
      unknown = 'https://member.test/users/unknown'
      stub_request(:get, unknown).to_return(status: 404)

      expect { sync(members: [owner.uri, actor_uri(local), unknown]) }.to_not raise_error
      expect(a_request(:get, unknown)).to have_been_made.at_least_once
    end

    it 'adds a member whose last known event is older' do
      perform({ 'id' => "#{room_uri}#remove/1", 'type' => 'Remove', 'target' => room_uri, 'object' => member.uri, 'published' => older }, owner)

      sync(members: [owner.uri, actor_uri(local), member.uri])

      expect(room.memberships.exists?(account: member)).to be(true)
      expect(ChatRosterState.find_by(chat_conversation: room, account: member).last_roster_at).to eq(Time.iso8601(roster_at))
    end

    it 'does not add a member whose removal is newer than the list' do
      perform({ 'id' => "#{room_uri}#remove/1", 'type' => 'Remove', 'target' => room_uri, 'object' => member.uri, 'published' => newer }, owner)

      sync(members: [owner.uri, actor_uri(local), member.uri])

      expect(room.memberships.exists?(account: member)).to be(false)
    end

    it 'removes a member whose last known event is older than the list' do
      perform({ 'id' => "#{room_uri}#add/1", 'type' => 'Add', 'target' => room_uri, 'object' => member.uri, 'published' => older }, owner)

      sync

      expect(room.memberships.exists?(account: member)).to be(false)
      expect(ChatRosterState.find_by(chat_conversation: room, account: member).last_roster_at).to eq(Time.iso8601(roster_at))
    end

    it 'keeps a member whose addition is newer than the list' do
      perform({ 'id' => "#{room_uri}#add/1", 'type' => 'Add', 'target' => room_uri, 'object' => member.uri, 'published' => newer }, owner)

      sync

      expect(room.memberships.exists?(account: member)).to be(true)
    end

    it 'removes a member with no known event as older than the list' do
      room.memberships.create!(account: member)
      ChatRosterState.where(chat_conversation: room, account: member).delete_all

      sync

      expect(room.memberships.exists?(account: member)).to be(false)
    end

    it 'makes an older Remove arriving later harmless once a member is confirmed' do
      room.memberships.create!(account: member)
      ChatRosterState.where(chat_conversation: room, account: member).delete_all
      sync(members: [owner.uri, actor_uri(local), member.uri])

      perform({ 'id' => "#{room_uri}#remove/1", 'type' => 'Remove', 'target' => room_uri, 'object' => member.uri, 'published' => older }, owner)

      expect(room.memberships.exists?(account: member)).to be(true)
    end

    it 'never puts a local account into a room it did not accept' do
      other_local = Fabricate(:user).account

      sync(members: [owner.uri, actor_uri(local), actor_uri(other_local)])

      expect(room.memberships.exists?(account: other_local)).to be(false)
    end

    it 'takes a local member out when the owner removed them and the Remove was lost' do
      second_local = Fabricate(:user).account
      second_local.user.settings[:chat_allow_group_invites] = true
      second_local.user.save!
      perform({ 'id' => "#{room_uri}#invite/1", 'type' => 'Invite', 'target' => actor_uri(second_local), 'published' => older, 'object' => { 'id' => room_uri, 'type' => 'Group', 'name' => 'Remote room', 'attributedTo' => owner.uri } }, owner)
      invitation = room.invitations.find_by!(invitee_account: second_local)
      service.accept_invitation(second_local, invitation)
      invitation.update!(updated_at: 1.hour.ago)

      sync(at: 1.minute.from_now.iso8601(3))

      expect(room.memberships.exists?(account: second_local)).to be(false)
    end

    it 'keeps a local member who accepted after the list was made' do
      second_local = Fabricate(:user).account
      second_local.user.settings[:chat_allow_group_invites] = true
      second_local.user.save!
      perform({ 'id' => "#{room_uri}#invite/1", 'type' => 'Invite', 'target' => actor_uri(second_local), 'published' => older, 'object' => { 'id' => room_uri, 'type' => 'Group', 'name' => 'Remote room', 'attributedTo' => owner.uri } }, owner)
      service.accept_invitation(second_local, room.invitations.find_by!(invitee_account: second_local))

      sync(at: 1.minute.ago.iso8601(3))

      expect(room.memberships.exists?(account: second_local)).to be(true)
    end

    it 'does not add a suspended account' do
      member.suspend!

      sync(members: [owner.uri, actor_uri(local), member.uri])

      expect(room.memberships.exists?(account: member)).to be(false)
    end

    it 'never removes the owner' do
      perform({ 'id' => "#{room_uri}#invite/1", 'type' => 'Invite', 'target' => actor_uri(local), 'published' => older, 'object' => { 'id' => room_uri, 'type' => 'Group', 'name' => 'Remote room', 'attributedTo' => owner.uri } }, owner)

      sync(members: [actor_uri(local)])

      expect(room.memberships.exists?(account: owner)).to be(true)
    end

    it 'ignores a list signed for by someone other than the owner' do
      sync(members: [owner.uri, actor_uri(local), member.uri], attributedTo: 'https://owner.test/users/other')

      expect(room.memberships.exists?(account: member)).to be(false)
    end

    it 'ignores a list with a time in the far future' do
      sync(members: [owner.uri, actor_uri(local), member.uri], at: 1.hour.from_now.iso8601(3))

      expect(room.memberships.exists?(account: member)).to be(false)
    end

    it 'does nothing with a Group from a server that does not send a list' do
      stub_group({ 'id' => room_uri, 'type' => 'Group', 'attributedTo' => owner.uri })

      expect { Sharlayan::ChatFederation::Roster.sync(room) }.to not_change(ChatMembership, :count)
    end

    it 'does not ask the owner when no local account can sign' do
      room.memberships.find_by!(account: local).destroy!
      stub = stub_group(group_json(members: [owner.uri], roster_at: roster_at))

      Sharlayan::ChatFederation::Roster.sync(room)

      expect(stub).to_not have_been_requested
    end

    it 'retries when the owner is briefly unavailable' do
      stub_request(:get, room_uri).to_return(status: 503)

      expect { Sharlayan::ChatFederation::Roster.sync(room) }.to raise_error(Mastodon::UnexpectedResponseError)
    end

    it 'runs from the worker' do
      stub_group(group_json(members: [owner.uri, actor_uri(local), member.uri], roster_at: roster_at))

      ChatRosterSyncWorker.new.perform(room.id)

      expect(room.memberships.exists?(account: member)).to be(true)
    end
  end

  describe 'relaying from a room owned here' do
    let(:owned) { service.create_conversation(local, type: :group, title: 'Room') }
    let(:reaction_id) { 'https://third.test/chat-reactions/1' }
    let(:message) { service.receive_group_message(member, room_uri: owned.uri, uri: message_uri, text: 'hi') }

    around { |example| Sidekiq::Testing.fake! { example.run } }

    before do
      owned.memberships.create!(account: member)
      owned.memberships.create!(account: third)
      message
      ActivityPub::DeliveryWorker.clear
    end

    def deliveries
      ActivityPub::DeliveryWorker.jobs.map { |job| [JSON.parse(job['args'][0]), job['args'][2]] }
    end

    def react_json
      { 'id' => reaction_id, 'type' => 'EmojiReact', 'actor' => third.uri, 'object' => message_uri, 'content' => '👍', '_misskey_reaction' => '👍' }
    end

    it 'announces an edit with the time it was made, to everyone but the author server' do
      perform({ 'id' => "#{message_uri}#update/1", 'type' => 'Update', 'object' => { 'id' => message_uri, 'type' => 'Note', 'attributedTo' => member.uri, '_misskey_talk' => true, '_misskey_content' => 'edited', '_misskey_chatRoom' => owned.uri, 'updated' => '2026-11-03T00:00:01.234Z' } }, member)

      expect(deliveries.size).to eq(1)
      announce, inbox = deliveries.first
      expect(inbox).to eq(third.inbox_url)
      expect(announce).to include('type' => 'Announce', 'actor' => actor_uri(local), 'object' => message_uri, 'context' => owned.uri, '_misskey_chatRoom' => owned.uri)
      expect(announce['id']).to eq("#{owned.uri}#relay/#{ERB::Util.url_encode(message_uri)}/#{Time.iso8601('2026-11-03T00:00:01.234Z').strftime('%s%L')}")
    end

    it 'does not announce an edit older than the one it has' do
      note = { 'id' => message_uri, 'type' => 'Note', 'attributedTo' => member.uri, '_misskey_talk' => true, '_misskey_content' => 'edited', '_misskey_chatRoom' => owned.uri }
      perform({ 'id' => "#{message_uri}#update/2", 'type' => 'Update', 'object' => note.merge('updated' => '2026-11-03T00:00:02.000Z') }, member)
      ActivityPub::DeliveryWorker.clear

      perform({ 'id' => "#{message_uri}#update/1", 'type' => 'Update', 'object' => note.merge('updated' => '2026-11-03T00:00:01.000Z') }, member)

      expect(deliveries).to be_empty
    end

    it 'announces a deletion with the original activity inside' do
      activity = { 'id' => "#{message_uri}#delete", 'type' => 'Delete', 'actor' => member.uri, 'object' => { 'id' => message_uri, 'type' => 'Tombstone' }, 'signature' => { 'type' => 'RsaSignature2017' } }

      perform(activity, member)

      expect(deliveries.size).to eq(1)
      announce, inbox = deliveries.first
      expect(inbox).to eq(third.inbox_url)
      expect(announce['id']).to eq("#{owned.uri}#relay/#{ERB::Util.url_encode(activity['id'])}")
      expect(announce['object']).to eq(activity.except('signature'))
    end

    it 'does not announce a deletion twice' do
      activity = { 'id' => "#{message_uri}#delete", 'type' => 'Delete', 'object' => { 'id' => message_uri, 'type' => 'Tombstone' } }

      2.times { perform(activity, member) }

      expect(deliveries.size).to eq(1)
    end

    it 'announces a reaction once with the original activity inside' do
      2.times { perform(react_json, third) }

      expect(deliveries.size).to eq(1)
      announce, inbox = deliveries.first
      expect(inbox).to eq(member.inbox_url)
      expect(announce['id']).to eq("#{owned.uri}#relay/#{ERB::Util.url_encode(reaction_id)}")
      expect(announce['object']).to include('id' => reaction_id, 'type' => 'EmojiReact', 'actor' => third.uri, 'object' => message_uri)
    end

    it 'announces the Undo of a reaction' do
      perform(react_json, third)
      expect(deliveries.size).to eq(1)
      ActivityPub::DeliveryWorker.clear

      perform({ 'id' => "#{reaction_id}/undo", 'type' => 'Undo', 'object' => react_json }, third)

      expect(deliveries.size).to eq(1)
      announce, = deliveries.first
      expect(announce['id']).to eq("#{owned.uri}#relay/#{ERB::Util.url_encode("#{reaction_id}/undo")}")
      expect(announce['object']).to include('type' => 'Undo')
    end

    it 'cannot announce an activity without an ID' do
      perform(react_json.except('id'), third)

      expect(message.reactions.reload.size).to eq(1)
      expect(deliveries).to be_empty
    end
  end

  describe 'receiving what the owner relays' do
    let(:note) { { '@context' => Sharlayan::ChatFederation::Payload::CONTEXT, 'id' => message_uri, 'type' => 'Note', 'attributedTo' => member.uri, '_misskey_talk' => true, '_misskey_chatRoom' => room_uri, 'context' => room_uri, '_misskey_content' => 'stored' } }
    let(:message) { service.receive_group_message(member, room_uri: room_uri, uri: message_uri, text: 'stored') }
    let(:reaction_id) { 'https://member.test/chat-reactions/1' }
    let(:react_json) { { 'id' => reaction_id, 'type' => 'EmojiReact', 'actor' => member.uri, 'object' => message_uri, 'content' => '👍', '_misskey_reaction' => '👍' } }

    before do
      room.memberships.create!(account: member)
      message
    end

    def stub_note(json = note)
      stub_request(:get, message_uri).to_return(status: 200, body: json.to_json, headers: { 'Content-Type' => 'application/activity+json' })
    end

    def announce(object, id: "#{room_uri}#relay/x", actor: owner)
      perform({ 'id' => id, 'type' => 'Announce', 'object' => object, 'context' => room_uri, '_misskey_chatRoom' => room_uri }, actor)
    end

    describe 'an edit' do
      let(:update_id) { "#{room_uri}#relay/#{ERB::Util.url_encode(message_uri)}/1762128001000" }

      it 'fetches the message again and applies it without a second copy' do
        stub_note(note.merge('_misskey_content' => 'edited', 'updated' => '2026-11-03T00:00:01.000Z'))

        announce(message_uri, id: update_id)

        expect(ChatMessage.where(uri: message_uri).count).to eq(1)
        expect(message.reload.text).to eq('edited')
        expect(message.edited_at).to eq(Time.iso8601('2026-11-03T00:00:01.000Z'))
      end

      it 'keeps a newer edit it already has' do
        message.update!(text: 'newer', edited_at: Time.iso8601('2026-11-03T00:00:05.000Z'))
        stub_note(note.merge('_misskey_content' => 'edited', 'updated' => '2026-11-03T00:00:01.000Z'))

        announce(message_uri, id: update_id)

        expect(message.reload.text).to eq('newer')
      end

      it 'does not fetch again for a repeated announcement of the message itself' do
        stub = stub_note

        announce(message_uri, id: "#{room_uri}#relay/#{ERB::Util.url_encode(message_uri)}")

        expect(stub).to_not have_been_requested
      end
    end

    describe 'a deletion' do
      let(:delete_json) { { 'id' => "#{message_uri}#delete", 'type' => 'Delete', 'actor' => member.uri, 'object' => { 'id' => message_uri, 'type' => 'Tombstone' } } }

      it 'applies one from the author' do
        announce(delete_json)

        expect(message.reload).to be_deleted
      end

      it 'applies one from an author who has left' do
        room.memberships.find_by!(account: member).destroy!

        announce(delete_json)

        expect(message.reload).to be_deleted
      end

      it 'applies one from the room owner' do
        announce(delete_json.merge('id' => 'https://owner.test/activities/1', 'actor' => owner.uri))

        expect(message.reload).to be_deleted
      end

      it 'ignores one from another member' do
        room.memberships.create!(account: third)

        announce(delete_json.merge('id' => 'https://third.test/activities/1', 'actor' => third.uri))

        expect(message.reload).to_not be_deleted
      end

      it 'ignores one for a message of another room' do
        other = service.receive_invite(local, owner, room_uri: 'https://owner.test/chat/rooms/other', title: 'Other').tap { |invitation| service.accept_invitation(local, invitation) }.chat_conversation
        other.memberships.create!(account: member)
        elsewhere = service.receive_group_message(member, room_uri: other.uri, uri: 'https://member.test/chat/messages/elsewhere', text: 'elsewhere')

        announce(delete_json.merge('object' => elsewhere.uri))

        expect(elsewhere.reload).to_not be_deleted
      end

      it 'ignores one that arrives from someone other than the room owner' do
        room.memberships.create!(account: third)

        announce(delete_json, actor: third)

        expect(message.reload).to_not be_deleted
      end

      it 'ignores one claiming to be from a local account' do
        local_message = room.messages.create!(account: local, text: 'mine', uri: 'https://cb6e6126.ngrok.io/chat/messages/1')

        announce(delete_json.merge('id' => "#{actor_uri(local)}/activities/1", 'actor' => actor_uri(local), 'object' => local_message.uri))

        expect(local_message.reload).to_not be_deleted
      end

      it 'ignores one whose ID is not on the actor server' do
        announce(delete_json.merge('id' => 'https://owner.test/activities/forged'))

        expect(message.reload).to_not be_deleted
      end

      it 'remembers one for a message that has not arrived from a known participant' do
        uri = 'https://member.test/chat/messages/later'

        announce(delete_json.merge('object' => uri))

        expect(service).to be_tombstone(uri, member)
      end

      it 'does not remember one for an account unknown to the room' do
        uri = 'https://third.test/chat/messages/later'

        announce(delete_json.merge('id' => 'https://third.test/activities/1', 'actor' => third.uri, 'object' => uri))

        expect(service).to_not be_tombstone(uri, third)
      end
    end

    describe 'a reaction' do
      it 'applies one from a current member' do
        room.memberships.create!(account: third)
        reaction = react_json.merge('id' => 'https://third.test/chat-reactions/1', 'actor' => third.uri)

        announce(reaction)

        expect(message.reactions.reload.map { |item| [item.account_id, item.reaction, item.uri] }).to eq([[third.id, '👍', reaction['id']]])
      end

      it 'accepts the Like form as well' do
        room.memberships.create!(account: third)

        announce(react_json.merge('id' => 'https://third.test/chat-reactions/1', 'actor' => third.uri, 'type' => 'Like'))

        expect(message.reactions.reload.size).to eq(1)
      end

      it 'keeps one copy when the reaction also arrives directly' do
        room.memberships.create!(account: third)
        reaction = react_json.merge('id' => 'https://third.test/chat-reactions/1', 'actor' => third.uri)

        announce(reaction)
        perform(reaction, third)

        expect(message.reactions.reload.size).to eq(1)
      end

      it 'waits for the member list when the actor is not a member' do
        expect { announce(react_json.merge('id' => 'https://third.test/chat-reactions/1', 'actor' => third.uri)) }
          .to raise_error(Sharlayan::ChatFederation::DependencyNotReadyError)

        expect(message.reactions.reload).to be_empty
      end

      it 'waits for a message that has not arrived' do
        expect { announce(react_json.merge('object' => 'https://member.test/chat/messages/later')) }
          .to raise_error(Sharlayan::ChatFederation::DependencyNotReadyError)
      end

      it 'ignores one for a message of another room' do
        other = service.receive_invite(local, owner, room_uri: 'https://owner.test/chat/rooms/other', title: 'Other').tap { |invitation| service.accept_invitation(local, invitation) }.chat_conversation
        other.memberships.create!(account: member)
        elsewhere = service.receive_group_message(member, room_uri: other.uri, uri: 'https://member.test/chat/messages/elsewhere', text: 'elsewhere')
        room.memberships.create!(account: third)

        announce(react_json.merge('id' => 'https://third.test/chat-reactions/1', 'actor' => third.uri, 'object' => elsewhere.uri))

        expect(elsewhere.reactions.reload).to be_empty
      end

      it 'ignores one on an ordinary status and boosts nothing' do
        status = Fabricate(:status, account: local)
        room.memberships.create!(account: third)

        expect { announce(react_json.merge('id' => 'https://third.test/chat-reactions/1', 'actor' => third.uri, 'object' => ActivityPub::TagManager.instance.uri_for(status))) }
          .to not_change(Favourite, :count)
          .and(not_change(Status, :count))
      end

      it 'ignores one claiming to be from a local account' do
        announce(react_json.merge('id' => "#{actor_uri(local)}/reactions/1", 'actor' => actor_uri(local)))

        expect(message.reactions.reload).to be_empty
      end

      it 'ignores one from a suspended account' do
        room.memberships.create!(account: third)
        third.suspend!

        announce(react_json.merge('id' => 'https://third.test/chat-reactions/1', 'actor' => third.uri))

        expect(message.reactions.reload).to be_empty
      end

      it 'takes a custom emoji from the reacting server and not from the relay' do
        room.memberships.create!(account: third)
        emoji_uri = 'https://third.test/emojis/wave'
        real_image = 'https://third.test/emoji/wave.png'
        emoji_json = { '@context' => 'https://www.w3.org/ns/activitystreams', 'id' => emoji_uri, 'type' => 'Emoji', 'name' => ':wave:', 'icon' => { 'type' => 'Image', 'url' => real_image } }
        stub_request(:get, emoji_uri).to_return(status: 200, body: emoji_json.to_json, headers: { 'Content-Type' => 'application/activity+json' })
        stub_request(:get, real_image).to_return(request_fixture('avatar.txt'))
        tag = { 'id' => emoji_uri, 'type' => 'Emoji', 'name' => ':wave:', 'icon' => { 'type' => 'Image', 'url' => 'https://owner.test/forged.png' } }

        announce(react_json.merge('id' => 'https://third.test/chat-reactions/1', 'actor' => third.uri, 'content' => ':wave:', '_misskey_reaction' => ':wave:', 'tag' => [tag]))

        expect(CustomEmoji.find_by(shortcode: 'wave', domain: third.domain).image_remote_url).to eq(real_image)
        expect(a_request(:get, 'https://owner.test/forged.png')).to_not have_been_made
      end

      it 'does not take a custom emoji whose ID is on another server' do
        room.memberships.create!(account: third)
        tag = { 'id' => 'https://owner.test/emojis/wave', 'type' => 'Emoji', 'name' => ':wave:', 'icon' => { 'type' => 'Image', 'url' => 'https://owner.test/forged.png' } }

        announce(react_json.merge('id' => 'https://third.test/chat-reactions/1', 'actor' => third.uri, 'content' => ':wave:', '_misskey_reaction' => ':wave:', 'tag' => [tag]))

        expect(CustomEmoji.find_by(shortcode: 'wave', domain: third.domain)).to be_nil
        expect(a_request(:get, 'https://owner.test/emojis/wave')).to_not have_been_made
      end
    end

    describe 'the Undo of a reaction' do
      before do
        room.memberships.create!(account: third)
        perform(third_reaction, third)
      end

      let(:third_reaction) { react_json.merge('id' => 'https://third.test/chat-reactions/1', 'actor' => third.uri) }

      it 'applies an inline one' do
        announce({ 'id' => 'https://third.test/chat-reactions/1/undo', 'type' => 'Undo', 'actor' => third.uri, 'object' => third_reaction })

        expect(message.reactions.reload).to be_empty
      end

      it 'applies one naming the reaction by URI' do
        announce({ 'id' => 'https://third.test/chat-reactions/1/undo', 'type' => 'Undo', 'actor' => third.uri, 'object' => third_reaction['id'] })

        expect(message.reactions.reload).to be_empty
      end

      it 'applies one from someone who has left' do
        room.memberships.find_by!(account: third).destroy!

        announce({ 'id' => 'https://third.test/chat-reactions/1/undo', 'type' => 'Undo', 'actor' => third.uri, 'object' => third_reaction })

        expect(message.reactions.reload).to be_empty
      end

      it 'ignores one by another account' do
        room.memberships.create!(account: Fabricate(:account, domain: 'fourth.test', uri: 'https://fourth.test/users/fourth'))
        fourth = Account.find_by!(uri: 'https://fourth.test/users/fourth')

        announce({ 'id' => 'https://fourth.test/undo/1', 'type' => 'Undo', 'actor' => fourth.uri, 'object' => third_reaction })

        expect(message.reactions.reload.size).to eq(1)
      end

      it 'ignores one claiming to be from a local account' do
        reaction = message.reactions.create!(account: local, reaction: '😀')

        announce({ 'id' => "#{actor_uri(local)}/undo/1", 'type' => 'Undo', 'actor' => actor_uri(local), 'object' => react_json.merge('actor' => actor_uri(local), 'content' => '😀') })

        expect(ChatMessageReaction.exists?(reaction.id)).to be(true)
      end

      it 'does not run anything else that can be undone' do
        follow = Fabricate(:follow, account: third, target_account: local)

        announce({ 'id' => 'https://third.test/undo/1', 'type' => 'Undo', 'actor' => third.uri, 'object' => { 'type' => 'Follow', 'id' => 'https://third.test/follows/1', 'actor' => third.uri, 'object' => actor_uri(local) } })

        expect(Follow.exists?(follow.id)).to be(true)
      end
    end

    it 'does nothing with any other activity' do
      follow_json = { 'id' => 'https://member.test/follows/1', 'type' => 'Follow', 'actor' => member.uri, 'object' => actor_uri(local) }

      expect { announce(follow_json) }.to not_change(Follow, :count).and(not_change(FollowRequest, :count))
    end

    describe 'a message on a server the room has no member on' do
      let(:foreign_uri) { 'https://unknown.test/chat/messages/1' }

      around { |example| Sidekiq::Testing.fake! { example.run } }

      before { ChatRosterSyncWorker.clear }

      it 'does not send a member signature there, asks for the member list and retries' do
        stub = stub_request(:get, foreign_uri).to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/activity+json' })

        expect { announce(foreign_uri) }.to raise_error(Sharlayan::ChatFederation::DependencyNotReadyError)

        expect(stub).to_not have_been_requested
        expect(sync_jobs).to eq([room.id])
      end

      it 'fetches once a member of that server is on the list' do
        note_there = note.merge('id' => foreign_uri, 'attributedTo' => 'https://unknown.test/users/new')
        stub_request(:get, foreign_uri).to_return(status: 200, body: note_there.to_json, headers: { 'Content-Type' => 'application/activity+json' })
        joined = Fabricate(:account, domain: 'unknown.test', uri: 'https://unknown.test/users/new', inbox_url: 'https://unknown.test/users/new/inbox')
        room.memberships.create!(account: joined)

        announce(foreign_uri)

        expect(ChatMessage.find_by(uri: foreign_uri).account).to eq(joined)
      end
    end
  end

  describe 'a URI-only Undo of a reaction' do
    let(:reaction_id) { 'https://member.test/chat-reactions/1' }
    let(:message) { room.messages.create!(account: local, text: 'hello', uri: 'https://cb6e6126.ngrok.io/chat/messages/1') }

    before { room.memberships.create!(account: member) }

    def react
      perform({ 'id' => reaction_id, 'type' => 'EmojiReact', 'object' => message.uri, 'content' => '👍' }, member)
    end

    it 'identifies the reaction by the activity it was made with' do
      react
      expect(message.reactions.reload.size).to eq(1)

      perform({ 'id' => "#{reaction_id}/undo", 'type' => 'Undo', 'object' => reaction_id }, member)

      expect(message.reactions.reload).to be_empty
    end

    it 'identifies it from an object with only an ID' do
      react

      perform({ 'id' => "#{reaction_id}/undo", 'type' => 'Undo', 'object' => { 'id' => reaction_id } }, member)

      expect(message.reactions.reload).to be_empty
    end

    it 'keeps working after the short-lived state has expired' do
      react
      service.redis.del("chat_reaction_active:#{member.id}:#{message.id}:#{Digest::SHA256.hexdigest('👍')}")

      perform({ 'id' => "#{reaction_id}/undo", 'type' => 'Undo', 'object' => reaction_id }, member)

      expect(message.reactions.reload).to be_empty
    end

    it 'does not let another account undo it' do
      react
      room.memberships.create!(account: third)

      perform({ 'id' => 'https://third.test/undo/1', 'type' => 'Undo', 'object' => reaction_id }, third)

      expect(message.reactions.reload.size).to eq(1)
    end

    it 'drops a reaction whose Undo overtook it' do
      perform({ 'id' => "#{reaction_id}/undo", 'type' => 'Undo', 'object' => reaction_id }, member)

      react

      expect(message.reactions.reload).to be_empty
    end
  end
end
