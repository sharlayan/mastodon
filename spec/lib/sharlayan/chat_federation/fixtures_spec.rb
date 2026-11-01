# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Sharlayan chat federation fixtures' do
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
    path = Rails.root.join('spec/fixtures/activitypub/chat', "#{name}.json")
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

  it 'accepts the room Add, Update, and Delete fixtures' do
    invitation = service.receive_invite(alice, bob, room_uri: 'https://remote.test/chat/rooms/g2', title: 'Remote room')
    conversation = invitation.chat_conversation

    perform(fixture('add'))
    expect(conversation.accounts).to include(carol)

    perform(fixture('update_room'))
    expect(conversation.reload.title).to eq('Updated room')

    perform(fixture('remove'))
    expect(conversation.accounts).not_to include(carol)

    perform(fixture('delete_room'))
    expect(ChatConversation.find_by(id: conversation.id)).to be_nil
  end
end