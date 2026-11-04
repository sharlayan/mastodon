# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Chat federation protocol' do
  let(:service) { Sharlayan::ChatService.new }
  let(:local) { Fabricate(:user).account }
  let(:owner) { Fabricate(:account, domain: 'owner.test', uri: 'https://owner.test/users/owner', inbox_url: 'https://owner.test/users/owner/inbox', can_chat: true) }
  let(:author) { Fabricate(:account, domain: 'author.test', uri: 'https://author.test/users/author', inbox_url: 'https://author.test/users/author/inbox', can_chat: true) }
  let(:room_uri) { 'https://owner.test/chat/rooms/abc123' }
  let(:message_uri) { 'https://author.test/chat/messages/m1' }
  let(:room) do
    invitation = service.receive_invite(local, owner, room_uri: room_uri, title: 'Remote room')
    service.accept_invitation(local, invitation)
    invitation.chat_conversation
  end

  before do
    Setting.chat_enabled = true
    Setting.chat_federation_enabled = true
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_federation_enabled = false
    Setting.chat_max_group_members = 50
    Setting.chat_max_attachments = 1
  end

  def perform(json, actor, **options)
    ActivityPub::Activity.factory(json, actor, **options).perform
  end

  def enqueued_activities(type)
    ActivityPub::DeliveryWorker.jobs.map { |job| [JSON.parse(job['args'][0]), job['args'][2]] }.select { |payload, _| payload['type'] == type }
  end

  def signature_for(account)
    a_request(:get, message_uri).with { |request| request.headers['Signature'].to_s.include?(ActivityPub::TagManager.instance.key_uri_for(account)) }
  end

  describe 'relayed Announce' do
    let(:note) do
      {
        '@context' => Sharlayan::ChatFederation::Payload::CONTEXT,
        'id' => message_uri,
        'type' => 'Note',
        'attributedTo' => author.uri,
        '_misskey_talk' => true,
        '_misskey_content' => 'relayed text',
        'context' => room_uri,
        '_misskey_chatRoom' => room_uri,
        'to' => [ActivityPub::TagManager.instance.uri_for(local)],
        'published' => '2026-11-03T00:00:00.000Z',
      }
    end
    let(:announce) do
      {
        'type' => 'Announce',
        'id' => "#{room_uri}#announce/1",
        'actor' => owner.uri,
        'object' => message_uri,
        'context' => room_uri,
        '_misskey_chatRoom' => room_uri,
        'to' => [ActivityPub::TagManager.instance.uri_for(local)],
      }
    end

    before do
      room.memberships.create!(account: author)
      local.user.update!(approved: true)
      author.follow!(owner)
      local.follow!(owner)
    end

    def stub_note(body = note, status: 200)
      stub_request(:get, message_uri).to_return(status: status, body: body.to_json, headers: { 'Content-Type' => 'application/activity+json' })
    end

    it 'stores the verified message as chat and never creates a reblog' do
      stub_note

      expect { perform(announce, owner) }.to change(ChatMessage, :count).by(1)
        .and(not_change(Status, :count))

      message = ChatMessage.find_by!(uri: message_uri)
      expect(message).to have_attributes(account: author, text: 'relayed text', chat_conversation: room)
      expect(signature_for(local)).to have_been_made
    end

    it 'does not fetch a message that already arrived directly' do
      stub = stub_note
      service.receive_group_message(author, room_uri: room_uri, uri: message_uri, text: 'direct')

      expect { perform(announce, owner) }.to_not change(ChatMessage, :count)
      expect(stub).to_not have_been_requested
    end

    it 'ignores an Announce from anyone but the room owner' do
      stub = stub_note

      expect { perform(announce.merge('actor' => author.uri), author) }.to_not change(ChatMessage, :count)
      expect(stub).to_not have_been_requested
    end

    it 'rejects a fetched object from another room' do
      stub_note(note.merge('context' => 'https://owner.test/chat/rooms/other', '_misskey_chatRoom' => 'https://owner.test/chat/rooms/other'))

      expect { perform(announce, owner) }.to_not change(ChatMessage, :count)
    end

    it 'rejects a fetched object that is not a chat message' do
      stub_note(note.except('_misskey_talk'))

      expect { perform(announce, owner) }
        .to not_change(ChatMessage, :count)
        .and(not_change(Status, :count))
    end

    it 'rejects a fetched object whose author is on another host' do
      stub_note(note.merge('attributedTo' => owner.uri))

      expect { perform(announce, owner) }.to_not change(ChatMessage, :count)
    end

    it 'retries when the author server does not know the member yet' do
      stub_note(status: 404)

      expect { perform(announce, owner) }.to raise_error(Sharlayan::ChatFederation::DependencyNotReadyError)
    end

    it 'stores the latest message when the member is known on retry' do
      updated_note = note.merge('_misskey_content' => 'edited text', 'updated' => '2026-11-03T00:01:00.000Z')
      stub_request(:get, message_uri).to_return(
        { status: 404 },
        { status: 200, body: updated_note.to_json, headers: { 'Content-Type' => 'application/activity+json' } }
      )

      expect { perform(announce, owner) }.to raise_error(Sharlayan::ChatFederation::DependencyNotReadyError)
      expect { perform(announce, owner) }.to change(ChatMessage, :count).by(1)
      expect(ChatMessage.find_by!(uri: message_uri).text).to eq('edited text')
    end

    it 'does not store a message deleted before the member is known on retry' do
      tombstone = { 'id' => message_uri, 'type' => 'Tombstone' }
      stub_request(:get, message_uri).to_return(
        { status: 404 },
        { status: 200, body: tombstone.to_json, headers: { 'Content-Type' => 'application/activity+json' } }
      )

      expect { perform(announce, owner) }.to raise_error(Sharlayan::ChatFederation::DependencyNotReadyError)
      expect { perform(announce, owner) }.to_not change(ChatMessage, :count)
    end

    it 'retries when the author has not been added to the room yet' do
      room.memberships.find_by!(account: author).destroy!
      stub_note

      expect { perform(announce, owner) }.to raise_error(Sharlayan::ChatFederation::DependencyNotReadyError)
    end

    it 'retries while the room has not arrived' do
      stub = stub_note

      expect { perform(announce.merge('context' => 'https://owner.test/chat/rooms/later', '_misskey_chatRoom' => 'https://owner.test/chat/rooms/later'), owner) }
        .to raise_error(Sharlayan::ChatFederation::DependencyNotReadyError)
      expect(stub).to_not have_been_requested
    end

    it 'treats a Tombstone as a deleted message' do
      stub_note({ 'id' => message_uri, 'type' => 'Tombstone' })

      expect { perform(announce, owner) }.to_not change(ChatMessage, :count)
    end

    it 'never reblogs a chat message announced without room fields' do
      stub = stub_note
      message = service.receive_group_message(author, room_uri: room_uri, uri: message_uri, text: 'direct')

      expect { perform(announce.except('context', '_misskey_chatRoom'), owner) }.to_not change(Status, :count)
      expect(message.reload.text).to eq('direct')
      expect(stub).to_not have_been_requested
    end

    it 'does not turn a chat note discovered through a plain Announce into a status or chat message' do
      stub_note
      plain = announce.except('context', '_misskey_chatRoom').merge('object' => 'https://author.test/notes/plain')
      stub_request(:get, 'https://author.test/notes/plain').to_return(status: 200, body: note.merge('id' => 'https://author.test/notes/plain').to_json, headers: { 'Content-Type' => 'application/activity+json' })

      expect { perform(plain, owner) }
        .to not_change(Status, :count)
        .and(not_change(ChatMessage, :count))
    end

    it 'does nothing when federation is disabled' do
      Setting.chat_federation_enabled = false
      stub = stub_note

      expect { perform(announce, owner) }.to_not change(Status, :count)
      expect(stub).to_not have_been_requested
    end
  end

  describe 'chat notes fetched outside the inbox' do
    it 'does not process a chat note as a remote status' do
      room.memberships.create!(account: author)
      body = {
        '@context' => Sharlayan::ChatFederation::Payload::CONTEXT,
        'id' => message_uri,
        'type' => 'Note',
        'attributedTo' => author.uri,
        '_misskey_talk' => true,
        'content' => 'hello',
        '_misskey_chatRoom' => room_uri,
      }

      result = nil
      expect { result = ActivityPub::FetchRemoteStatusService.new.call(message_uri, prefetched_body: body) }
        .to not_change(Status, :count)
        .and(not_change(ChatMessage, :count))
      expect(result).to be_nil
    end
  end

  describe 'relaying from a Mastodon-owned room' do
    let(:owned) { service.create_conversation(local, type: :group, title: 'Owned room') }
    let(:peer) { Fabricate(:account, domain: 'peer.test', uri: 'https://peer.test/users/peer', inbox_url: 'https://peer.test/users/peer/inbox', can_chat: true) }
    let(:sibling) { Fabricate(:account, domain: 'author.test', username: 'sibling', uri: 'https://author.test/users/sibling', inbox_url: 'https://author.test/users/sibling/inbox', can_chat: true) }

    before do
      owned.memberships.create!(account: author)
      owned.memberships.create!(account: peer)
      owned.memberships.create!(account: sibling)
      ActivityPub::DeliveryWorker.clear
    end

    it 'announces a new remote message once to members on other servers' do
      Sidekiq::Testing.fake! do
        service.receive_group_message(author, room_uri: owned.uri, uri: message_uri, text: 'hello')
        service.receive_group_message(author, room_uri: owned.uri, uri: message_uri, text: 'hello')
      end

      activities = enqueued_activities('Announce')
      expect(activities.map(&:last)).to contain_exactly(peer.inbox_url)
      expect(activities.first.first).to include(
        'id' => "#{owned.uri}#relay/#{ERB::Util.url_encode(message_uri)}",
        'actor' => ActivityPub::TagManager.instance.uri_for(local),
        'object' => message_uri,
        'context' => owned.uri,
        '_misskey_chatRoom' => owned.uri,
        'to' => include(peer.uri)
      )
    end

    it 'does not announce local messages, which already reach every known member' do
      Sidekiq::Testing.fake! { service.create_message(local, owned, text: 'hello') }

      expect(enqueued_activities('Announce')).to be_empty
    end

    it 'does not relay messages in rooms owned elsewhere' do
      room.memberships.create!(account: author)
      room.memberships.create!(account: peer)
      ActivityPub::DeliveryWorker.clear

      Sidekiq::Testing.fake! { service.receive_group_message(author, room_uri: room_uri, uri: message_uri, text: 'hello') }

      expect(enqueued_activities('Announce')).to be_empty
    end
  end

  describe 'room Update ordering' do
    def update(name, updated: nil, archived: nil, summary: 'about')
      object = { 'id' => room_uri, 'type' => 'Group', 'name' => name, 'summary' => summary, 'attributedTo' => owner.uri }
      object['updated'] = updated if updated
      object['_misskey_chatArchived'] = archived unless archived.nil?
      { 'type' => 'Update', 'actor' => owner.uri, 'object' => object }
    end

    before { room }

    it 'ignores an Update older than the one already applied' do
      perform(update('newer', updated: '2026-11-03T00:00:02.000Z', archived: true), owner)
      perform(update('older', updated: '2026-11-03T00:00:01.000Z', archived: false), owner)

      expect(room.reload).to have_attributes(title: 'newer', archived?: true)
    end

    it 'applies a newer Update and an Update with the same version' do
      perform(update('first', updated: '2026-11-03T00:00:01.000Z'), owner)
      perform(update('second', updated: '2026-11-03T00:00:01.000Z'), owner)
      expect(room.reload.title).to eq('second')

      perform(update('third', updated: '2026-11-03T00:00:02.000Z'), owner)
      expect(room.reload.title).to eq('third')
    end

    it 'applies Updates without a version in arrival order' do
      perform(update('versioned', updated: '2026-11-03T00:00:01.000Z'), owner)
      perform(update('unversioned'), owner)
      perform(update('stale', updated: '2026-11-03T00:00:00.000Z'), owner)

      expect(room.reload.title).to eq('unversioned')
    end

    it 'treats an unparsable version as missing' do
      perform(update('first', updated: '2026-11-03T00:00:01.000Z'), owner)
      perform(update('second', updated: 'not a date'), owner)

      expect(room.reload.title).to eq('second')
    end

    it 'does not broadcast an ignored Update' do
      perform(update('newer', updated: '2026-11-03T00:00:02.000Z'), owner)
      stream = []
      allow_any_instance_of(Sharlayan::ChatService).to receive(:broadcast) { |*args| stream << args } # rubocop:disable RSpec/AnyInstance

      perform(update('older', updated: '2026-11-03T00:00:01.000Z'), owner)

      expect(stream).to be_empty
    end

    it 'waits for the room when an Update overtakes its Invite' do
      expect { perform(update('early').deep_merge('object' => { 'id' => 'https://owner.test/chat/rooms/later' }), owner) }
        .to raise_error(Sharlayan::ChatFederation::DependencyNotReadyError)
    end

    it 'truncates an oversized room name and description like the sender does' do
      perform(update('n' * 300, summary: 'd' * 3000), owner)

      expect(room.reload.title.length).to eq(256)
      expect(room.description.length).to eq(2048)
    end

    it 'keeps the description when the Update does not carry one' do
      perform(update('first', summary: 'kept'), owner)
      perform({ 'type' => 'Update', 'actor' => owner.uri, 'object' => { 'id' => room_uri, 'type' => 'Group', 'name' => 'second', 'attributedTo' => owner.uri } }, owner)

      expect(room.reload).to have_attributes(title: 'second', description: 'kept')
    end

    it 'keeps the newer state when an Invite snapshot arrives late' do
      perform(update('newer', updated: '2026-11-03T00:00:02.000Z'), owner)
      other = Fabricate(:user).account

      invite = {
        'type' => 'Invite', 'actor' => owner.uri,
        'target' => ActivityPub::TagManager.instance.uri_for(other),
        'object' => { 'id' => room_uri, 'type' => 'Group', 'name' => 'older', 'attributedTo' => owner.uri, 'updated' => '2026-11-03T00:00:01.000Z' }
      }
      perform(invite, owner)

      expect(room.reload.title).to eq('newer')
      expect(room.invitations.pending.where(invitee_account: other)).to exist
    end

    it 'ignores an Update older than the Invite that created the room' do
      other = Fabricate(:user).account
      later = 'https://owner.test/chat/rooms/later'
      perform({
        'type' => 'Invite', 'actor' => owner.uri,
        'target' => ActivityPub::TagManager.instance.uri_for(other),
        'object' => { 'id' => later, 'type' => 'Group', 'name' => 'invite state', 'attributedTo' => owner.uri, 'updated' => '2026-11-03T00:00:02.000Z' }
      }, owner)

      perform(update('older', updated: '2026-11-03T00:00:01.000Z').deep_merge('object' => { 'id' => later }), owner)

      expect(ChatConversation.find_by!(uri: later).title).to eq('invite state')
    end

    it 'accepts a re-invitation that reopens a room archived in the local copy' do
      room.update!(archived_at: 1.hour.ago)
      other = Fabricate(:user).account

      perform({
        'type' => 'Invite', 'actor' => owner.uri,
        'target' => ActivityPub::TagManager.instance.uri_for(other),
        'object' => { 'id' => room_uri, 'type' => 'Group', 'name' => 'reopened', 'attributedTo' => owner.uri, 'updated' => '2026-11-03T00:00:03.000Z', '_misskey_chatArchived' => false }
      }, owner)

      expect(room.reload).to have_attributes(archived?: false, title: 'reopened')
      expect(room.invitations.pending.where(invitee_account: other)).to exist
    end
  end

  describe 'sending room state' do
    let(:owned) { service.create_conversation(local, type: :group, title: 'Owned room') }

    before do
      owned.memberships.create!(account: author)
      owned.invitations.create!(inviter_account: local, invitee_account: owner)
      ActivityPub::DeliveryWorker.clear
    end

    it 'sends a strictly newer updated value with each room change' do
      Sidekiq::Testing.fake! do
        freeze_time do
          service.update_conversation(local, owned, { title: 'one' })
          service.update_conversation(local, owned, { title: 'two' })
          service.archive(local, owned, archived: true)
        end
      end

      versions = enqueued_activities('Update').select { |_, inbox| inbox == author.inbox_url }.map { |payload, _| payload.dig('object', 'updated') }
      expect(versions.size).to eq(3)
      expect(versions).to all(match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\z/))
      expect(versions.uniq.size).to eq(3)
      expect(versions.sort).to eq(versions)
    end

    it 'does not advance the version for a message, which does not change room state' do
      version = Sharlayan::ChatFederation::Payload.room(owned)['updated']

      travel 1.minute do
        service.create_message(local, owned, text: 'hello')
        expect(Sharlayan::ChatFederation::Payload.room(owned.reload)['updated']).to eq(version)
      end
    end

    it 'reads the full locked state so concurrent edits are not reverted' do
      stale = ChatConversation.find(owned.id)
      service.update_conversation(local, owned, { title: 'new title' })
      ActivityPub::DeliveryWorker.clear

      Sidekiq::Testing.fake! { service.update_conversation(local, stale, { description: 'new description' }) }

      expect(enqueued_activities('Update').first.first.fetch('object')).to include('name' => 'new title', 'summary' => 'new description')
    end
  end

  describe 'chat messages identified by a stored URI' do
    let(:foreign_uri) { 'https://author.test/notes/not-a-chat-path' }
    let!(:message) do
      room.memberships.create!(account: author)
      service.receive_group_message(author, room_uri: room_uri, uri: foreign_uri, text: 'stored')
    end

    it 'applies an Update without _misskey_talk' do
      perform({ 'type' => 'Update', 'actor' => author.uri, 'object' => { 'id' => foreign_uri, 'type' => 'Note', 'attributedTo' => author.uri, 'content' => 'edited', 'updated' => '2026-11-03T00:00:00.000Z' } }, author)

      expect(message.reload.text).to eq('edited')
    end

    it 'applies a Delete' do
      perform({ 'type' => 'Delete', 'actor' => author.uri, 'object' => foreign_uri }, author)

      expect(message.reload).to be_deleted
    end

    context 'with a reaction from a member' do
      let(:reactor) { owner }

      it 'applies a Like carrying only _misskey_reaction and its Undo' do
        like = { 'type' => 'Like', 'id' => 'https://owner.test/likes/1', 'actor' => reactor.uri, 'object' => foreign_uri, '_misskey_reaction' => '👍' }

        perform(like, reactor)
        expect(message.reactions.where(account: reactor, reaction: '👍')).to exist

        perform({ 'type' => 'Undo', 'id' => 'https://owner.test/likes/1/undo', 'actor' => reactor.uri, 'object' => like }, reactor)
        expect(message.reactions.where(account: reactor)).to_not exist
      end

      it 'applies an EmojiReact and its Undo' do
        react = { 'type' => 'EmojiReact', 'id' => 'https://owner.test/reacts/1', 'actor' => reactor.uri, 'object' => foreign_uri, 'content' => '👍' }

        perform(react, reactor)
        expect(message.reactions.where(account: reactor)).to exist

        perform({ 'type' => 'Undo', 'id' => 'https://owner.test/reacts/1/undo', 'actor' => reactor.uri, 'object' => react }, reactor)
        expect(message.reactions.where(account: reactor)).to_not exist
      end

      it 'does not store a plain Like with no reaction as a favourite or a reaction' do
        expect { perform({ 'type' => 'Like', 'actor' => reactor.uri, 'object' => foreign_uri }, reactor) }
          .to not_change(ChatMessageReaction, :count)
          .and(not_change(Favourite, :count))
      end
    end
  end

  describe 'statuses whose URIs merely look like chat paths' do
    let(:status_uri) { 'https://author.test/chat/messages/actually-a-status' }
    let!(:status) { Fabricate(:status, account: author, uri: status_uri) }

    it 'still deletes the status' do
      perform({ 'type' => 'Delete', 'actor' => author.uri, 'object' => status_uri }, author)

      expect(Status.find_by(id: status.id)).to be_nil
    end

    it 'treats a URI with a chat path prefix and further segments as ordinary' do
      expect(Sharlayan::ChatFederation::Incoming.chat_delete?('object' => 'https://author.test/chat/rooms/1/extra')).to be(false)
    end
  end

  describe 'group messages whose note does not address a local account' do
    it 'stores the message when the room has local members' do
      room.memberships.create!(account: author)
      note = { 'id' => message_uri, 'type' => 'Note', 'attributedTo' => author.uri, '_misskey_talk' => true, '_misskey_content' => 'hi', '_misskey_chatRoom' => room_uri, 'to' => [] }

      expect { perform({ 'type' => 'Create', 'actor' => author.uri, 'object' => note }, author) }.to change(ChatMessage, :count).by(1)
    end

    it 'waits for the membership when Add has not arrived' do
      room
      note = { 'id' => message_uri, 'type' => 'Note', 'attributedTo' => author.uri, '_misskey_talk' => true, '_misskey_content' => 'hi', '_misskey_chatRoom' => room_uri }

      expect { perform({ 'type' => 'Create', 'actor' => author.uri, 'object' => note }, author) }
        .to raise_error(Sharlayan::ChatFederation::DependencyNotReadyError)
    end

    it 'skips malformed recipients of a direct message without failing' do
      local.user.settings[:chat_policy] = 'everyone'
      local.user.save!
      note = { 'id' => message_uri, 'type' => 'Note', 'attributedTo' => author.uri, '_misskey_talk' => true, '_misskey_content' => 'hi', 'to' => [nil, { 'name' => 'x' }, 'http://[invalid', ActivityPub::TagManager.instance.uri_for(local)] }

      expect { perform({ 'type' => 'Create', 'actor' => author.uri, 'object' => note }, author) }.to change(ChatMessage, :count).by(1)
    end
  end

  describe 'Add' do
    before { room }

    it 'retries when the member account cannot be fetched yet' do
      allow(ActivityPub::FetchRemoteAccountService).to receive(:new).and_return(instance_double(ActivityPub::FetchRemoteAccountService, call: nil))

      expect { perform({ 'type' => 'Add', 'actor' => owner.uri, 'target' => room_uri, 'object' => 'https://new.test/users/late' }, owner) }
        .to raise_error(Sharlayan::ChatFederation::DependencyNotReadyError)
    end

    it 'records a member even if an archive overtook the Add' do
      room.update!(archived_at: Time.current)

      perform({ 'type' => 'Add', 'actor' => owner.uri, 'target' => room_uri, 'object' => author.uri }, owner)

      expect(room.memberships.where(account: author)).to exist
    end
  end

  describe 'concurrent first direct messages' do
    it 'keeps the message when another worker created the conversation first' do
      key = [local.id, author.id].sort.join(':')
      local.user.settings[:chat_policy] = 'everyone'
      local.user.save!
      winner = ChatConversation.new(conversation_type: :direct, direct_key: key)
      allow(ChatConversation).to receive(:lock).and_wrap_original do |original, *args|
        unless winner.persisted?
          winner.save!
          winner.memberships.create!([{ account: local }, { account: author }])
          next ChatConversation.none
        end
        original.call(*args)
      end

      message = service.receive_direct_message(local, author, uri: message_uri, text: 'first')

      expect(message.chat_conversation).to eq(winner)
    end
  end

  describe 'local reactions' do
    let(:conversation) { service.create_conversation(local, type: :group, title: 'Room') }
    let(:message) { service.receive_group_message(author, room_uri: conversation.uri, uri: message_uri, text: 'hi') }

    before do
      conversation.memberships.create!(account: author)
      message
      ActivityPub::DeliveryWorker.clear
    end

    it 'does not send a second activity for a repeated reaction' do
      first = nil
      second = nil
      Sidekiq::Testing.fake! do
        first = service.react(local, message, '👍')
        second = service.react(local, message, '👍')
      end

      expect(second).to eq(first)
      expect(enqueued_activities('EmojiReact').size).to eq(1)
    end

    it 'does not send an Undo for a reaction that was not made' do
      Sidekiq::Testing.fake! { service.unreact(local, message, '👍') }

      expect(enqueued_activities('Undo')).to be_empty
    end

    it 'sends one Undo with the ID of the reaction it cancels' do
      record = nil
      Sidekiq::Testing.fake! do
        record = service.react(local, message, '👍')
        service.unreact(local, message, '👍')
        service.unreact(local, message, '👍')
      end

      undo = enqueued_activities('Undo')
      expect(undo.size).to eq(1)
      expect(undo.first.first.dig('object', 'id')).to end_with("/chat/reactions/#{record.id}")
    end
  end

  describe 'leaving and deleting' do
    let(:conversation) { service.create_conversation(local, type: :group, title: 'Room') }
    let(:other) { Fabricate(:user).account }

    it 'refuses to leave a direct chat, which would delete it for the other side too' do
      other.user.settings[:chat_policy] = 'everyone'
      other.user.save!
      direct = service.create_conversation(local, type: :direct, account_ids: [other.id])

      expect { service.leave(local, direct) }.to raise_error(Sharlayan::ChatService::Error)
      expect(ChatConversation.exists?(direct.id)).to be(true)
    end

    it 'does not resend Delete for a message that is already deleted' do
      conversation.memberships.create!(account: author)
      message = service.create_message(local, conversation, text: 'hello')
      ActivityPub::DeliveryWorker.clear

      Sidekiq::Testing.fake! do
        service.delete_message(local, message)
        service.delete_message(local, message.reload)
      end

      expect(enqueued_activities('Delete').size).to eq(1)
    end

    it 'schedules cleanup when the last local member leaves a remote room' do
      room
      allow(ChatConversationCleanupWorker).to receive(:perform_in)

      service.leave(local, room)

      expect(ChatConversationCleanupWorker).to have_received(:perform_in).with(ChatConversationCleanupWorker::CLEANUP_DELAY, room.id)
    end

    it 'keeps a room with a recent pending invitation during cleanup' do
      service.receive_invite(other, owner, room_uri: room_uri, title: 'Remote room')
      room.memberships.find_by!(account: local).destroy!
      allow(ChatConversationCleanupWorker).to receive(:perform_at)

      ChatConversationCleanupWorker.new.perform(room.id)

      expect(ChatConversation.exists?(room.id)).to be(true)
      expect(ChatConversationCleanupWorker).to have_received(:perform_at)
    end

    it 'removes an abandoned remote room during cleanup' do
      room.memberships.find_by!(account: local).destroy!

      ChatConversationCleanupWorker.new.perform(room.id)

      expect(ChatConversation.exists?(room.id)).to be(false)
    end
  end

  describe 'participant checks' do
    let(:suspended) { Fabricate(:user).account.tap(&:suspend!) }
    let(:conversation) { service.create_conversation(local, type: :group, title: 'Room') }
    let(:silenced) { Fabricate(:account, domain: 'quiet.test', uri: 'https://quiet.test/users/q', inbox_url: 'https://quiet.test/users/q/inbox', can_chat: true, silenced: true) }

    it 'refuses to start a chat with a suspended account' do
      expect { service.create_conversation(local, type: :direct, account_ids: [suspended.id]) }.to raise_error(Sharlayan::ChatService::Error)
    end

    it 'refuses to invite a suspended account' do
      expect { service.invite(local, conversation, suspended) }.to raise_error(Sharlayan::ChatService::Forbidden)
    end

    it 'does not let a silenced account start a direct chat with someone who does not follow it' do
      local.user.settings[:chat_policy] = 'everyone'
      local.user.save!

      expect { service.receive_direct_message(local, silenced, uri: 'https://quiet.test/chat/messages/1', text: 'spam') }
        .to raise_error(Sharlayan::ChatService::Forbidden)
    end

    it 'lets a silenced account start a direct chat with a local follower' do
      local.user.settings[:chat_policy] = 'everyone'
      local.user.save!
      local.follow!(silenced)

      expect { service.receive_direct_message(local, silenced, uri: 'https://quiet.test/chat/messages/1', text: 'hello') }
        .to change(ChatMessage, :count).by(1)
    end

    it 'refuses a group invitation from a silenced account the invitee does not follow' do
      expect { service.receive_invite(local, silenced, room_uri: 'https://quiet.test/chat/rooms/1', title: 'Spam') }
        .to raise_error(Sharlayan::ChatService::Forbidden)
    end
  end

  describe 'incoming attachments' do
    before { room.memberships.create!(account: author) }

    it 'stores a bounded description and ignores non-string fields' do
      attachments = [{ 'url' => 'https://author.test/a.png', 'mediaType' => 'image/png', 'name' => 'd' * (MediaAttachment::MAX_DESCRIPTION_HARD_LENGTH_LIMIT + 1) }, { 'url' => 'https://author.test/b.png', 'mediaType' => { 'x' => 1 }, 'name' => { 'x' => 1 } }]
      message = nil
      Setting.chat_max_attachments = 2

      expect { message = service.receive_group_message(author, room_uri: room_uri, uri: message_uri, text: 'x', attachments: attachments) }
        .to change(MediaAttachment, :count).by(2)

      first, second = message.media_attachments.sort_by(&:id)
      expect(first.description.length).to be <= MediaAttachment::MAX_DESCRIPTION_HARD_LENGTH_LIMIT
      expect(second.description).to be_nil
      expect(second.file_content_type).to be_nil
    end
  end

  describe 'incoming attachment types' do
    before { room.memberships.create!(account: author) }

    it 'keeps the message when the declared media type is not supported' do
      attachments = [{ 'url' => 'https://author.test/file.pdf', 'mediaType' => 'application/pdf', 'name' => 'A file' }]

      message = service.receive_group_message(author, room_uri: room_uri, uri: message_uri, text: 'see attached', attachments: attachments)

      expect(message.text).to eq('see attached')
      expect(message.media_attachments.first).to have_attributes(file_content_type: nil, type: 'unknown', remote_url: 'https://author.test/file.pdf')
    end

    it 'reads the description from summary as other software sends it' do
      attachments = [{ 'url' => 'https://author.test/a.png', 'mediaType' => 'image/png', 'summary' => 'From summary' }]

      message = service.receive_group_message(author, room_uri: room_uri, uri: message_uri, text: 'x', attachments: attachments)

      expect(message.media_attachments.first.description).to eq('From summary')
    end
  end

  describe 'chat media lifecycle' do
    let(:conversation) { service.create_conversation(local, type: :group, title: 'Room') }
    let(:media) { Fabricate(:media_attachment, account: local, status: nil) }
    let(:token) { Fabricate(:accessible_access_token, resource_owner_id: local.user.id, scopes: 'write') }

    it 'removes the attachment when its message is destroyed' do
      message = service.create_message(local, conversation, text: 'x', media_ids: [media.id])

      message.destroy!

      expect(MediaAttachment.exists?(media.id)).to be(false)
    end

    it 'removes the attachment when its room is destroyed' do
      service.create_message(local, conversation, text: 'x', media_ids: [media.id])

      service.destroy_conversation(local, conversation)

      expect(MediaAttachment.exists?(media.id)).to be(false)
    end

    it 'does not let the sender silently change a sent attachment' do
      service.create_message(local, conversation, text: 'x', media_ids: [media.id])

      put "/api/v1/media/#{media.id}", params: { description: 'changed' }, headers: { 'Authorization' => "Bearer #{token.token}" }

      expect(response).to have_http_status(404)
      expect(media.reload.description).to_not eq('changed')
    end
  end

  describe 'reaction bookkeeping' do
    let(:conversation) { service.create_conversation(local, type: :group, title: 'Room') }
    let(:message) { service.create_message(local, conversation, text: 'hello') }

    before { conversation.memberships.create!(account: author) }

    it 'removes a reaction with several activity IDs through an Undo without an ID' do
      service.react_remote(author, message, '👍', activity_id: 'https://author.test/r/1')
      service.react_remote(author, message, '👍', activity_id: 'https://author.test/r/2')

      service.unreact_remote(author, message, '👍')

      expect(message.reactions.where(account: author)).to_not exist
    end

    it 'imports a custom emoji without holding the message lock' do
      baseline = ChatMessage.connection.open_transactions
      depth = nil

      service.react_remote(author, message, ':blob:', activity_id: 'https://author.test/r/3') do
        depth = ChatMessage.connection.open_transactions
      end

      expect(depth).to eq(baseline)
    end
  end

  describe 'event and delivery timing' do
    let(:conversation) { service.create_conversation(local, type: :group, title: 'Room') }

    before { conversation.memberships.create!(account: author) }

    it 'does not deliver or announce anything from a transaction that rolls back' do
      ActivityPub::DeliveryWorker.clear
      published = []
      allow(service).to receive(:redis).and_return(instance_double(Redis, publish: nil).tap { |redis| allow(redis).to receive(:publish) { |*args| published << args } })

      Sidekiq::Testing.fake! do
        ChatConversation.transaction do
          service.create_message(local, conversation, text: 'rolled back')
          raise ActiveRecord::Rollback
        end
      end

      expect(ActivityPub::DeliveryWorker.jobs).to be_empty
      expect(published).to be_empty
    end

    it 'only publishes to local members' do
      channels = []
      allow(service).to receive(:redis).and_return(instance_double(Redis).tap { |redis| allow(redis).to receive(:publish) { |channel, _| channels << channel } })

      service.update_conversation(local, conversation, { title: 'renamed' })

      expect(channels).to include("timeline:#{local.id}")
      expect(channels).to_not include("timeline:#{author.id}")
    end
  end

  describe 'repeated and overtaking invitation activities' do
    let(:invite) do
      {
        'type' => 'Invite', 'actor' => owner.uri, 'published' => '2026-11-03T00:00:00Z',
        'target' => ActivityPub::TagManager.instance.uri_for(local),
        'object' => { 'id' => room_uri, 'type' => 'Group', 'name' => 'Room', 'attributedTo' => owner.uri }
      }
    end
    let(:undo) { { 'type' => 'Undo', 'actor' => owner.uri, 'published' => '2026-11-03T00:00:01Z', 'object' => invite.slice('type', 'actor', 'target').merge('object' => room_uri) } }

    it 'does not ask a member again when an Invite is redelivered' do
      perform(invite, owner)
      service.accept_invitation(local, ChatInvitation.pending.find_by!(invitee_account: local))
      ActivityPub::DeliveryWorker.clear

      Sidekiq::Testing.fake! { perform(invite, owner) }

      expect(ChatInvitation.pending.where(invitee_account: local)).to_not exist
      expect(enqueued_activities('Accept').map(&:last)).to eq([owner.inbox_url])
    end

    it 'honors an Undo that overtook its Invite' do
      perform(undo, owner)
      perform(invite, owner)

      expect(ChatConversation.find_by(uri: room_uri)).to be_nil
      expect(ChatInvitation.pending.where(invitee_account: local)).to_not exist
    end

    it 'still accepts a later re-invitation after that Undo' do
      perform(undo, owner)
      perform(invite.merge('published' => '2026-11-03T00:00:02Z'), owner)

      expect(ChatInvitation.pending.where(invitee_account: local)).to exist
    end
  end

  describe 'rooms larger than the local limit' do
    it 'keeps tracking members of a room owned elsewhere' do
      room
      Setting.chat_max_group_members = 2

      perform({ 'type' => 'Add', 'actor' => owner.uri, 'target' => room_uri, 'object' => author.uri }, owner)

      expect(room.memberships.where(account: author)).to exist
    end

    it 'still enforces the local limit in rooms owned here' do
      conversation = service.create_conversation(local, type: :group, title: 'Room')
      conversation.memberships.create!(account: author)
      Setting.chat_max_group_members = 2
      invitee = Fabricate(:user).account

      expect { service.invite(local, conversation, invitee) }.to raise_error(Sharlayan::ChatService::Error, /too many/)
    end
  end

  describe 'remote departures' do
    it 'tells local clients a member left, matching what happens on join' do
      room.memberships.create!(account: author)
      events = []
      allow(service).to receive(:broadcast_to).and_wrap_original do |original, account, event, *rest|
        events << event
        original.call(account, event, *rest)
      end

      service.receive_remove(author, room_uri: room_uri, account_uri: author.uri)

      expect(events).to include('chat.member_leave')
    end
  end

  describe 'writing while federation is off' do
    it 'refuses a message that could never reach the other side' do
      room.memberships.create!(account: author)
      Setting.chat_federation_enabled = false

      expect { service.create_message(local, room, text: 'lost') }.to raise_error(Sharlayan::ChatService::Error, /federation/)
    end

    it 'keeps purely local rooms writable' do
      conversation = service.create_conversation(local, type: :group, title: 'Room')
      Setting.chat_federation_enabled = false

      expect { service.create_message(local, conversation, text: 'fine') }.to change(ChatMessage, :count).by(1)
    end
  end

  describe 'starting a chat with a stale remote account' do
    let(:stale) { Fabricate(:account, domain: 'stale.test', uri: 'https://stale.test/users/s', inbox_url: 'https://stale.test/users/s/inbox', chat_scope: 'everyone', last_webfingered_at: 2.days.ago) }

    it 'rechecks whether the server can chat before starting' do
      allow(ActivityPub::FetchRemoteAccountService).to receive(:new).and_return(instance_double(ActivityPub::FetchRemoteAccountService).tap do |fetcher|
        allow(fetcher).to receive(:call) { stale.update!(can_chat: false) }
      end)

      expect { service.create_conversation(local, type: :direct, account_ids: [stale.id]) }.to raise_error(Sharlayan::ChatService::Forbidden)
    end
  end

  describe 'roleplay instances' do
    it 'keeps chat local, as the mode promises for everything else' do
      Sharlayan::RoleplayForcedSettings.apply_forced!

      expect(Setting.chat_federation_enabled).to be(false)
    end
  end

  describe 'native API authentication' do
    it 'answers 401 when the token is missing' do
      get '/api/v1/chat/conversations'

      expect(response).to have_http_status(401)
    end
  end

  describe 'object endpoints' do
    let(:conversation) { service.create_conversation(local, type: :group, title: 'Room') }

    def signed_get(path, account)
      get path, headers: { 'Accept' => 'application/activity+json' }, sign_with: account
    end

    it 'does not serve a stored remote message under a local URL' do
      conversation.memberships.create!(account: author)
      message = service.receive_group_message(author, room_uri: conversation.uri, uri: message_uri, text: 'hi')

      signed_get("/chat/messages/#{message.id}", author)

      expect(response).to have_http_status(404)
    end

    it 'answers 404 for a direct conversation instead of failing' do
      author.update!(chat_scope: 'everyone')
      direct = service.create_conversation(local, type: :direct, account_ids: [author.id])

      signed_get("/chat/rooms/#{direct.id}", author)

      expect(response).to have_http_status(404)
    end

    it 'answers 404 for the local copy of a room owned elsewhere' do
      room.memberships.create!(account: author)

      signed_get("/chat/rooms/#{room.id}", author)

      expect(response).to have_http_status(404)
    end
  end

  describe 'chat media in limited federation mode' do
    let(:conversation) { service.create_conversation(local, type: :group, title: 'Room') }
    let(:media) { Fabricate(:media_attachment, account: local, status: nil) }

    before do
      conversation.memberships.create!(account: author)
      service.create_message(local, conversation, text: 'hello', media_ids: [media.id])
      allow(Rails.configuration.x.mastodon).to receive(:limited_federation_mode).and_return(true)
    end

    it 'lets a remote server fetch with a valid federation token' do
      get "/media_proxy/#{media.id}/original", params: { token: Sharlayan::ChatFederation::MediaToken.generate(media, domain: author.domain) }

      expect(response).to have_http_status(302)
      expect(response.location).to_not include('/auth/sign_in')
    end

    it 'keeps requiring a login with an invalid token' do
      get "/media_proxy/#{media.id}/original", params: { token: 'invalid' }

      expect(response.location.to_s).to include('/auth/sign_in')
    end
  end

  describe 'Misskey account lookup' do
    let!(:unapproved) { Fabricate(:user, account_attributes: { username: 'pending_lookup' }).tap { |user| user.update!(approved: false) }.account }
    let!(:approved) { Fabricate(:user, account_attributes: { username: 'pending_friend' }).account }
    let(:token) { Fabricate(:accessible_access_token, resource_owner_id: local.user.id, scopes: 'read').token }

    before { Setting.misskey_compat_enabled = true }
    after { Setting.misskey_compat_enabled = false }

    it 'does not expose accounts that cannot be discovered through regular search' do
      post '/api/users/search-by-username-and-host', params: { i: token, username: 'pending', host: '.' }, as: :json

      ids = response.parsed_body.pluck('id')
      expect(ids).to include(MisskeyCompat::MiId.encode(approved.id))
      expect(ids).to_not include(MisskeyCompat::MiId.encode(unapproved.id))
    end

    it 'does not expose the instance actor' do
      post '/api/users/search-by-username-and-host', params: { i: token, username: Account.representative.username, host: '.' }, as: :json

      expect(response.parsed_body.pluck('id')).to_not include(MisskeyCompat::MiId.encode(Account.representative.id))
    end
  end
end
