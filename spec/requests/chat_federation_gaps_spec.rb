# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Chat federation gaps' do
  let(:service) { Sharlayan::ChatService.new }
  let(:owner) { Fabricate(:user).account }
  let(:remote) { Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/bob', inbox_url: 'https://remote.test/users/bob/inbox', can_chat: true, chat_scope: 'everyone') }
  let(:room) { service.create_conversation(owner, type: :group, title: 'Room') }

  before do
    Setting.chat_enabled = true
    Setting.chat_federation_enabled = true
    Setting.chat_soft_delete_enabled = false
    Setting.chat_max_group_members = 50
    Setting.chat_max_attachments = 4
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_federation_enabled = false
    Setting.chat_soft_delete_enabled = false
    Setting.chat_max_group_members = 50
    Setting.chat_max_attachments = 1
  end

  def perform(json, actor = remote)
    ActivityPub::Activity.factory(json, actor, delivered_to_account_id: owner.id).perform
  end

  def delivered_to(account)
    ActivityPub::DeliveryWorker.jobs.filter_map { |job| JSON.parse(job['args'][0]) if job['args'][2] == account.inbox_url }
  end

  def delivered_types(account)
    delivered_to(account).pluck('type')
  end

  def note_json(uri = 'https://remote.test/chat/messages/1', **extra)
    { 'type' => 'Create', 'actor' => remote.uri, 'object' => {
      'id' => uri, 'type' => 'Note', 'attributedTo' => remote.uri,
      '_misskey_talk' => true, 'content' => 'hello',
      'to' => [ActivityPub::TagManager.instance.uri_for(owner)]
    }.merge(extra.transform_keys(&:to_s)) }
  end

  def accept_json(conversation)
    { 'type' => 'Accept', 'actor' => remote.uri, 'object' => {
      'type' => 'Invite', 'actor' => owner.uri, 'target' => remote.uri,
      'object' => { 'id' => conversation.uri, 'type' => 'Group' }
    } }
  end

  describe 'incoming replies' do
    let(:direct) { service.create_conversation(owner, type: :direct, account_ids: [remote.id]) }

    it 'keeps the reply target of a federated message' do
      target = service.create_message(owner, direct, text: 'first')

      perform(note_json(inReplyTo: target.uri))

      expect(ChatMessage.find_by(uri: 'https://remote.test/chat/messages/1').reply_to).to eq(target)
    end

    it 'keeps a message whose reply target is unknown' do
      direct

      perform(note_json(inReplyTo: 'https://remote.test/chat/messages/unknown'))

      expect(ChatMessage.find_by(uri: 'https://remote.test/chat/messages/1')).to have_attributes(reply_to: nil, text: 'hello')
    end

    it 'does not link a reply target from another conversation' do
      direct
      other_room = service.create_conversation(owner, type: :group, title: 'Elsewhere')
      foreign = service.create_message(owner, other_room, text: 'elsewhere')

      perform(note_json(inReplyTo: foreign.uri))

      expect(ChatMessage.find_by(uri: 'https://remote.test/chat/messages/1').reply_to).to be_nil
    end
  end

  describe 'incoming media' do
    let(:attachment) { { 'type' => 'Document', 'url' => 'https://remote.test/media_proxy/1/original?token=abc', 'mediaType' => 'video/mp4' } }

    before { service.create_conversation(owner, type: :direct, account_ids: [remote.id]) }

    it 'downloads a federated attachment as soon as it arrives' do
      perform(note_json(attachment: [attachment]))

      media = ChatMessage.find_by(uri: 'https://remote.test/chat/messages/1').media_attachments.first
      expect(RedownloadMediaWorker.jobs.pluck('args')).to contain_exactly([media.id])
    end

    it 'records the declared media type until the file is downloaded' do
      perform(note_json(attachment: [attachment]))

      expect(ChatMessage.find_by(uri: 'https://remote.test/chat/messages/1').media_attachments.first.type).to eq('video')
    end

    it 'does not download media from a domain whose media is rejected' do
      Fabricate(:domain_block, domain: 'remote.test', severity: :noop, reject_media: true)

      perform(note_json(attachment: [attachment]))

      expect(ChatMessage.find_by(uri: 'https://remote.test/chat/messages/1').media_attachments.size).to eq(1)
      expect(RedownloadMediaWorker.jobs).to be_empty
    end
  end

  describe Sharlayan::ChatFederation::MediaToken do
    let(:media) { Fabricate(:media_attachment, account: owner, status: nil) }

    it 'outlives delivery retries and receivers that cache lazily' do
      token = described_class.generate(media)

      travel 30.days

      expect(described_class.valid?(token, media)).to be(true)
    end

    it 'still expires' do
      token = described_class.generate(media)

      travel described_class::TTL + 1.day

      expect(described_class.valid?(token, media)).to be(false)
    end
  end

  describe 'pending remote invitees' do
    before { service.invite(owner, room, remote) }

    it 'tells them when the room is deleted' do
      service.destroy_conversation(owner, room)

      expect(delivered_types(remote)).to include('Delete')
    end

    it 'tells them when an admin deletes the room' do
      service.destroy_conversation_as_admin(room)

      expect(delivered_types(remote)).to include('Delete')
    end

    it 'tells them when the owner account is purged' do
      room
      service.purge_account(owner)

      expect(delivered_types(remote)).to include('Delete')
    end

    it 'tells them when the room is renamed' do
      service.update_conversation(owner, room, { title: 'Renamed' })

      expect(delivered_to(remote).find { |payload| payload['type'] == 'Update' }.dig('object', 'name')).to eq('Renamed')
    end

    it 'does not send them messages before they join' do
      service.create_message(owner, room, text: 'members only')

      expect(delivered_types(remote)).to_not include('Create')
    end
  end

  describe 'a refused Accept' do
    before { service.invite(owner, room, remote) }

    it 'removes the invitee on their server when the room is full' do
      Setting.chat_max_group_members = 1

      perform(accept_json(room))

      expect(delivered_to(remote).find { |payload| payload['type'] == 'Remove' })
        .to include('actor' => ActivityPub::TagManager.instance.uri_for(owner), 'object' => remote.uri, 'target' => room.uri)
      expect(room.memberships.exists?(account: remote)).to be(false)
      expect(room.invitations.pending.exists?(invitee_account: remote)).to be(false)
    end

    it 'removes the invitee when the invitation was cancelled' do
      service.cancel_invitation(owner, room.invitations.pending.find_by!(invitee_account: remote))

      perform(accept_json(room))

      expect(delivered_types(remote)).to include('Remove')
    end

    it 'does not remove a member when Accept is redelivered' do
      perform(accept_json(room))
      perform(accept_json(room))

      expect(room.memberships.exists?(account: remote)).to be(true)
      expect(delivered_types(remote)).to_not include('Remove')
    end

    it 'leaves rooms owned elsewhere alone' do
      mirror = ChatConversation.create!(conversation_type: :group, owner_account: remote, title: 'Mirror', uri: 'https://remote.test/chat/rooms/8')

      perform(accept_json(mirror))

      expect(delivered_types(remote)).to_not include('Remove')
    end
  end

  describe 'an Accept from an account that was never invited' do
    it 'does not answer, so that rooms cannot be discovered' do
      perform(accept_json(room))

      expect(delivered_types(remote)).to_not include('Remove')
      expect(room.memberships.exists?(account: remote)).to be(false)
    end
  end

  describe 'a suspended remote member' do
    before do
      room.memberships.create!(account: remote)
      remote.suspend!
    end

    it 'stops receiving what the room sends' do
      message = service.create_message(owner, room, text: 'sent after suspension')
      service.update_message(owner, message, text: 'edited after suspension')
      service.update_conversation(owner, room, { title: 'Renamed' })

      expect(delivered_to(remote)).to be_empty
    end

    it 'is not told who joined' do
      other = Fabricate(:account, domain: 'other.test', uri: 'https://other.test/users/carol', inbox_url: 'https://other.test/users/carol/inbox', can_chat: true)
      service.invite(owner, room, other)

      perform(accept_json(room), other)

      expect(room.memberships.exists?(account: other)).to be(true)
      expect(delivered_types(remote)).to_not include('Add')
    end

    it 'still learns what was removed' do
      message = service.create_message(owner, room, text: 'sent after suspension')
      service.delete_message(owner, message)
      service.destroy_conversation(owner, room)

      expect(delivered_types(remote)).to eq(%w(Delete Delete))
    end
  end

  describe 'archiving' do
    let(:mirror) do
      ChatConversation.create!(conversation_type: :group, owner_account: remote, title: 'Mirror', uri: 'https://remote.test/chat/rooms/9').tap do |record|
        record.memberships.create!(account: remote, role: :owner)
        record.memberships.create!(account: owner)
      end
    end

    def room_update(archived)
      object = { 'id' => mirror.uri, 'type' => 'Group', 'name' => 'Mirror', 'attributedTo' => remote.uri }
      object['_misskey_chatArchived'] = archived unless archived.nil?
      { 'type' => 'Update', 'actor' => remote.uri, 'object' => object }
    end

    it 'federates the archived state to members and pending invitees' do
      member = Fabricate(:account, domain: 'other.test', uri: 'https://other.test/users/carol', inbox_url: 'https://other.test/users/carol/inbox')
      room.memberships.create!(account: member)
      service.invite(owner, room, remote)

      service.archive(owner, room, archived: true)

      [member, remote].each do |account|
        expect(delivered_to(account).find { |payload| payload['type'] == 'Update' }.dig('object', '_misskey_chatArchived')).to be(true)
      end
    end

    it 'federates unarchiving' do
      room.memberships.create!(account: remote)
      service.archive(owner, room, archived: true)
      ActivityPub::DeliveryWorker.jobs.clear

      service.archive(owner, room, archived: false)

      expect(delivered_to(remote).find { |payload| payload['type'] == 'Update' }.dig('object', '_misskey_chatArchived')).to be(false)
    end

    it 'applies the archived state from the room owner' do
      perform(room_update(true))
      expect(mirror.reload).to be_archived

      perform(room_update(false))
      expect(mirror.reload).to_not be_archived
    end

    it 'leaves the state alone when a peer does not send it' do
      mirror.update!(archived_at: Time.current)

      perform(room_update(nil))

      expect(mirror.reload).to be_archived
    end

    it 'ignores the state from anyone but the owner' do
      intruder = Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/mallory', inbox_url: 'https://remote.test/users/mallory/inbox')

      perform(room_update(true).merge('actor' => intruder.uri), intruder)

      expect(mirror.reload).to_not be_archived
    end
  end

  describe 'chat capability' do
    def actor_json(account)
      serialized_record_json(account, ActivityPub::ActorSerializer, adapter: ActivityPub::Adapter)
    end

    it 'advertises chat when federation is enabled' do
      expect(actor_json(owner)).to include('_misskey_canChat' => true, '_misskey_chatScope' => 'mutual')
    end

    it 'explicitly refuses chat while federation is disabled' do
      Setting.chat_federation_enabled = false

      expect(actor_json(owner)).to include('_misskey_canChat' => false)
    end

    it 'explicitly refuses chat while chat is disabled' do
      Setting.chat_enabled = false

      expect(actor_json(owner)).to include('_misskey_canChat' => false)
    end

    def process_actor(**extra)
      payload = {
        id: 'https://foo.test',
        type: 'Actor',
        inbox: 'https://foo.test/inbox',
        preferredUsername: 'alice',
      }.merge(extra).with_indifferent_access

      webfinger = { subject: 'acct:alice@foo.test', links: [{ rel: 'self', href: payload['id'], type: 'application/activity+json' }] }
      stub_request(:get, 'https://foo.test/.well-known/webfinger?resource=acct:alice@foo.test')
        .to_return(body: webfinger.to_json, headers: { 'Content-Type': 'application/jrd+json' })

      ActivityPub::ProcessAccountService.new.call(payload)
    end

    it 'does not assume chat support from an actor that does not declare it' do
      expect(process_actor.can_chat).to be(false)
    end

    it 'records chat support from an actor that declares it' do
      expect(process_actor(_misskey_canChat: true).can_chat).to be(true)
    end

    it 'does not start a direct chat with an account without chat support' do
      remote.update!(can_chat: false)

      expect { service.create_conversation(owner, type: :direct, account_ids: [remote.id]) }
        .to raise_error(Sharlayan::ChatService::Forbidden)
    end

    it 'does not invite an account without chat support' do
      remote.update!(can_chat: false)

      expect { service.invite(owner, room, remote) }.to raise_error(Sharlayan::ChatService::Forbidden)
    end

    it 'does not create a group with an account without chat support' do
      remote.update!(can_chat: false)

      expect { service.create_conversation(owner, type: :group, title: 'Room', account_ids: [remote.id]) }
        .to raise_error(Sharlayan::ChatService::Forbidden)
    end
  end

  describe 'status media serialization' do
    let(:status) { Fabricate(:status, account: owner) }
    let!(:media) { Fabricate(:media_attachment, account: owner, status: status) }

    def chat_media_queries
      queries = []
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
        queries << payload[:sql] if payload[:sql].include?('chat_message_media_attachments')
      end
      yield
      queries
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    it 'serves the edit history of a status with media' do
      status.snapshot!(at_time: status.created_at, rate_limit: false)
      status.update!(text: 'Edited')
      status.snapshot!(rate_limit: false)
      token = Fabricate(:accessible_access_token, resource_owner_id: owner.user.id, scopes: 'read:statuses')

      get "/api/v1/statuses/#{status.id}/history", headers: { 'Authorization' => "Bearer #{token.token}" }

      expect(response).to have_http_status(200)
      expect(response.parsed_body.first[:media_attachments].pluck(:id)).to contain_exactly(media.id.to_s)
    end

    it 'does not query chat tables for media attached to a status' do
      queries = chat_media_queries { REST::MediaAttachmentSerializer.new(media.reload).as_json }

      expect(queries).to be_empty
    end

    it 'still recognizes media attached to a chat message' do
      direct = service.create_conversation(owner, type: :direct, account_ids: [remote.id])
      chat_media = Fabricate(:media_attachment, account: owner, status: nil)
      service.create_message(owner, direct, text: 'with media', media_ids: [chat_media.id])

      expect(chat_media.reload.chat_attachment?).to be(true)
    end
  end

  describe 'unread state' do
    let(:conversation) { service.create_conversation(owner, type: :direct, account_ids: [remote.id]) }

    def unread_for(account)
      REST::ChatConversationSerializer.new(conversation.reload, current_account: account).as_json[:unread]
    end

    def receive_note(uri)
      perform(note_json(uri))
    end

    before do
      conversation
      Setting.chat_soft_delete_enabled = true
    end

    it 'stays read after the sender hides their latest message' do
      receive_note('https://remote.test/chat/messages/1')
      service.mark_read(owner, conversation)
      service.delete_message(owner, service.create_message(owner, conversation, text: 'mine'))

      expect(unread_for(owner)).to be(false)
    end

    it 'turns unread when a newer message arrives' do
      service.create_message(owner, conversation, text: 'mine')
      receive_note('https://remote.test/chat/messages/2')

      expect(unread_for(owner)).to be(true)
    end

    it 'is unread when nothing has been read yet' do
      receive_note('https://remote.test/chat/messages/3')

      expect(unread_for(owner)).to be(true)
    end
  end
end
