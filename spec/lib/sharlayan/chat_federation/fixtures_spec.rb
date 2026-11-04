# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Chat federation fixtures', type: :model do
  let(:alice) { Fabricate(:user).account }
  let(:bob) { Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/bob', inbox_url: 'https://remote.test/users/bob/inbox', can_chat: true, chat_scope: 'everyone') }
  let(:carol) { Fabricate(:account, domain: 'other.test', uri: 'https://other.test/users/carol', inbox_url: 'https://other.test/users/carol/inbox') }
  let(:service) { Sharlayan::ChatService.new }
  let(:local_uri) { ActivityPub::TagManager.instance.uri_for(alice) }

  before do
    Setting.chat_enabled = true
    Setting.chat_federation_enabled = true
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_federation_enabled = false
  end

  def fixture(name, room: 'https://remote.test/chat/rooms/g2')
    path = Rails.root.join('spec', 'fixtures', 'activitypub', 'chat', "#{name}.json")
    JSON.parse(path.read
      .gsub('__LOCAL__', local_uri)
      .gsub('__CAROL__', carol.uri)
      .gsub('__ROOM__', room))
  end

  def perform(json, account = bob, **options)
    ActivityPub::Activity.factory(json, account, **options).perform
  end

  it 'accepts the direct Create, Update, reaction, Undo, and Delete fixtures' do
    perform(fixture('create_direct'), bob, delivered_to_account_id: alice.id)
    message = ChatMessage.find_by!(uri: 'https://remote.test/chat/messages/1')
    expect(message.text).to eq('hello')

    perform(fixture('update'), bob)
    expect(message.reload.text).to eq('edited')

    perform(fixture('delete'), bob)
    expect(message.reload.deleted_at).to be_present
  end

  it 'accepts the reaction and Undo fixtures for a locally authored message' do
    conversation = service.create_conversation(alice, type: :direct, account_ids: [bob.id])
    message = service.create_message(alice, conversation, text: 'hello')
    message.update!(uri: 'https://remote.test/chat/messages/1')

    expect { perform(fixture('reaction'), bob) }.to change { message.reactions.count }.by(1)
    expect { perform(fixture('undo_reaction'), bob) }.to change { message.reactions.count }.by(-1)
  end

  it 'accepts a group Create fixture for a room member' do
    conversation = service.create_conversation(alice, type: :group, account_ids: [], title: 'Local room')
    conversation.memberships.create!(account: bob)
    room = Sharlayan::ChatFederation::Payload.room_uri(conversation)

    perform(fixture('create_group', room: room), bob, delivered_to_account_id: alice.id)

    expect(conversation.messages.find_by(uri: 'https://remote.test/chat/messages/group-1')).to be_present
  end

  context 'with a server that names the room only in @context' do
    def legacy_create(room)
      json = fixture('create_group', room: room)
      json['object'] = json['object'].except('context', '_misskey_chatRoom').merge('@context' => room)
      json
    end

    let(:conversation) do
      service.create_conversation(alice, type: :group, account_ids: [], title: 'Local room').tap do |room|
        room.memberships.create!(account: bob)
      end
    end
    let(:room_id) { Sharlayan::ChatFederation::Payload.room_uri(conversation).split('/').last }
    let(:received) { conversation.messages.find_by(uri: 'https://remote.test/chat/messages/group-1') }

    it 'accepts a message that names the room by its own URI' do
      perform(legacy_create(Sharlayan::ChatFederation::Payload.room_uri(conversation)), bob, delivered_to_account_id: alice.id)

      expect(received).to be_present
    end

    it 'finds the room when the sender names it under its own host' do
      expect { perform(legacy_create("https://remote.test/chat/rooms/#{room_id}"), bob, delivered_to_account_id: alice.id) }
        .to_not(change { ChatConversation.chat_direct.count })

      expect(received).to be_present
    end

    it 'finds a mirrored room owned by another server' do
      owner = Fabricate(:account, domain: 'owner.test', uri: 'https://owner.test/users/owner')
      mirror = ChatConversation.create!(conversation_type: :group, owner_account: owner, title: 'Mirror', uri: 'https://owner.test/chat/rooms/abc123')
      [owner, alice, bob].each { |account| mirror.memberships.create!(account: account) }

      perform(legacy_create('https://remote.test/chat/rooms/abc123'), bob, delivered_to_account_id: alice.id)

      expect(mirror.messages.find_by(uri: 'https://remote.test/chat/messages/group-1')).to be_present
    end

    it 'does not let a sender name a room under another host by its ID' do
      expect { perform(legacy_create("https://other.test/chat/rooms/#{room_id}"), bob, delivered_to_account_id: alice.id) }
        .to raise_error(Sharlayan::ChatFederation::DependencyNotReadyError)

      expect(received).to be_nil
    end

    it 'does not deliver into a room the sender is not a member of' do
      outsider = Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/outsider')
      json = legacy_create("https://remote.test/chat/rooms/#{room_id}")
      json['actor'] = outsider.uri
      json['object']['attributedTo'] = outsider.uri

      expect { perform(json, outsider, delivered_to_account_id: alice.id) }
        .to raise_error(Sharlayan::ChatFederation::DependencyNotReadyError)

      expect(conversation.messages.where(account: outsider)).to be_empty
    end

    context 'with an invitation or membership named by another URI' do
      def invite_response(type, room)
        {
          '@context' => 'https://www.w3.org/ns/activitystreams',
          'id' => 'https://remote.test/activities/1',
          'type' => type,
          'actor' => bob.uri,
          'object' => { 'type' => 'Invite', 'actor' => local_uri, 'object' => { 'type' => 'Group', 'id' => room }, 'target' => bob.uri },
        }
      end

      let(:room) { service.create_conversation(alice, type: :group, account_ids: [], title: 'Local room') }
      let(:id) { Sharlayan::ChatFederation::Payload.room_uri(room).split('/').last }

      before { room.invitations.create!(inviter_account: alice, invitee_account: bob) }

      it 'accepts an invitation to the room named under the sender host' do
        perform(invite_response('Accept', "https://remote.test/chat/rooms/#{id}"), bob)

        expect(room.memberships.exists?(account: bob)).to be true
        expect(room.invitations.find_by(invitee_account: bob)).to be_accepted
      end

      it 'rejects an invitation to the room named by a path guessed from an actor URI' do
        perform(invite_response('Reject', "https://#{Rails.configuration.x.web_domain}/ap/chat/rooms/#{id}"), bob)

        expect(room.invitations.find_by(invitee_account: bob)).to be_rejected
      end

      it 'lets a member leave a room named by a path guessed from an actor URI' do
        perform(invite_response('Accept', "https://remote.test/chat/rooms/#{id}"), bob)

        perform({
          '@context' => 'https://www.w3.org/ns/activitystreams',
          'id' => 'https://remote.test/activities/2',
          'type' => 'Remove',
          'actor' => bob.uri,
          'object' => bob.uri,
          'target' => "https://#{Rails.configuration.x.web_domain}/ap/chat/rooms/#{id}",
        }, bob)

        expect(room.memberships.exists?(account: bob)).to be false
      end

      it 'does not accept an invitation for an account that was not invited' do
        outsider = Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/outsider')
        json = invite_response('Accept', "https://remote.test/chat/rooms/#{id}")
        json['actor'] = outsider.uri

        perform(json, outsider)

        expect(room.memberships.exists?(account: outsider)).to be false
      end
    end

    it 'does not guess when the ID matches two rooms of the sender' do
      owner = Fabricate(:account, domain: 'owner.test', uri: 'https://owner.test/users/owner')
      rooms = %w(https://owner.test/chat/rooms/abc123 https://elsewhere.test/chat/rooms/abc123).map do |uri|
        ChatConversation.create!(conversation_type: :group, owner_account: owner, title: 'Mirror', uri: uri).tap do |room|
          [owner, alice, bob].each { |account| room.memberships.create!(account: account) }
        end
      end

      expect { perform(legacy_create('https://remote.test/chat/rooms/abc123'), bob, delivered_to_account_id: alice.id) }
        .to raise_error(Sharlayan::ChatFederation::DependencyNotReadyError)

      expect(ChatMessage.where(chat_conversation: rooms)).to be_empty
    end
  end

  it 'does not open a direct conversation for a group message' do
    conversation = service.create_conversation(alice, type: :group, account_ids: [], title: 'Local room')
    conversation.memberships.create!(account: bob)
    conversation.update!(archived_at: Time.current)

    expect { perform(fixture('create_group', room: Sharlayan::ChatFederation::Payload.room_uri(conversation)), bob, delivered_to_account_id: alice.id) }
      .to_not(change { ChatConversation.where(conversation_type: :direct).count })

    expect(ChatMessage.find_by(uri: 'https://remote.test/chat/messages/group-1')).to be_nil
  end

  it 'accepts the Invite fixture and creates a mirror room' do
    perform(fixture('invite'))

    conversation = ChatConversation.find_by!(uri: 'https://remote.test/chat/rooms/g2')
    expect(conversation.owner_account).to eq(bob)
    expect(conversation.invitations.pending.find_by(invitee_account: alice)).to be_present
  end

  it 'accepts the Accept and Reject fixtures for a local invitation' do
    accepted = service.create_conversation(alice, type: :group, account_ids: [bob.id], title: 'Local room')
    room = Sharlayan::ChatFederation::Payload.room_uri(accepted)

    perform(fixture('accept', room: room))
    expect(accepted.memberships.exists?(account: bob)).to be(true)

    rejected = service.create_conversation(alice, type: :group, account_ids: [bob.id], title: 'Another room')
    another_room = Sharlayan::ChatFederation::Payload.room_uri(rejected)

    perform(fixture('reject', room: another_room))
    expect(rejected.invitations.find_by(invitee_account: bob)).to be_rejected
  end

  it 'stores the relayed message from the Announce fixture without creating a reblog' do
    invitation = service.receive_invite(alice, bob, room_uri: 'https://remote.test/chat/rooms/g2', title: 'Remote room')
    service.accept_invitation(alice, invitation)
    conversation = ChatConversation.find_by!(uri: 'https://remote.test/chat/rooms/g2')
    conversation.memberships.create!(account: carol)
    note = {
      'id' => 'https://other.test/chat/messages/relayed', 'type' => 'Note', 'attributedTo' => carol.uri,
      '_misskey_talk' => true, '_misskey_content' => 'relayed', '_misskey_chatRoom' => conversation.uri,
      '@context' => Sharlayan::ChatFederation::Payload::CONTEXT
    }
    stub_request(:get, note['id']).to_return(body: note.to_json, headers: { 'Content-Type' => 'application/activity+json' })

    expect { perform(fixture('announce')) }.to change(ChatMessage, :count).by(1).and(not_change(Status, :count))
    expect(ChatMessage.find_by!(uri: note['id'])).to have_attributes(account: carol, text: 'relayed')
  end

  it 'accepts the room Add, Update, and Delete fixtures' do
    invitation = service.receive_invite(alice, bob, room_uri: 'https://remote.test/chat/rooms/g2', title: 'Remote room')
    conversation = invitation.chat_conversation

    perform(fixture('add'))
    expect(conversation.accounts).to include(carol)

    perform(fixture('update_room'))
    expect(conversation.reload.title).to eq('Updated room')

    perform(fixture('remove'))
    expect(conversation.accounts).to_not include(carol)

    perform(fixture('delete_room'))
    expect(ChatConversation.find_by(id: conversation.id)).to be_nil
  end
end
