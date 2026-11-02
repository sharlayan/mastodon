# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityPub::Activity::Invite, type: :model do
  let(:alice) { Fabricate(:user).account }
  let(:bob) { Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/bob', inbox_url: 'https://remote.test/users/bob/inbox') }
  let(:carol) { Fabricate(:account, domain: 'other.test', uri: 'https://other.test/users/carol', inbox_url: 'https://other.test/users/carol/inbox') }
  let(:service) { Sharlayan::ChatService.new }
  let(:room_uri) { 'https://remote.test/chat/rooms/9' }
  let!(:conversation) do
    invitation = service.receive_invite(alice, bob, room_uri: room_uri, title: 'Remote room')
    invitation.chat_conversation
  end

  before do
    Setting.chat_enabled = true
    Setting.chat_federation_enabled = true
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_federation_enabled = false
  end

  it 'adds a member from Add' do
    add = {
      'type' => 'Add',
      'actor' => bob.uri,
      'target' => room_uri,
      'object' => carol.uri,
    }

    expect { ActivityPub::Activity.factory(add, bob).perform }
      .to change { conversation.memberships.count }.by(1)
    expect(conversation.accounts).to include(carol)
  end

  it 'updates the mirror room from Update' do
    update = {
      'type' => 'Update',
      'actor' => bob.uri,
      'object' => {
        'id' => room_uri,
        'type' => 'Group',
        'name' => 'New name',
        'summary' => 'New description',
        'attributedTo' => bob.uri,
      },
    }

    ActivityPub::Activity.factory(update, bob).perform

    expect(conversation.reload.title).to eq('New name')
    expect(conversation.description).to eq('New description')
  end

  it 'deletes the mirror room from Delete' do
    delete = {
      'type' => 'Delete',
      'actor' => bob.uri,
      'object' => { 'id' => room_uri, 'type' => 'Tombstone', 'formerType' => 'Group' },
    }

    ActivityPub::Activity.factory(delete, bob).perform

    expect(ChatConversation.find_by(id: conversation.id)).to be_nil
  end

  it 'ignores a room update from a non-owner' do
    update = {
      'type' => 'Update',
      'actor' => carol.uri,
      'object' => {
        'id' => room_uri,
        'type' => 'Group',
        'name' => 'Hijacked',
        'attributedTo' => carol.uri,
      },
    }

    ActivityPub::Activity.factory(update, carol).perform

    expect(conversation.reload.title).to eq('Remote room')
  end
end
RSpec.describe 'ActivityPub chat invitations' do
  let(:owner) { Fabricate(:user).account }
  let(:bob) { Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/bob', inbox_url: 'https://remote.test/users/bob/inbox') }
  let(:service) { Sharlayan::ChatService.new }
  let(:conversation) { service.create_conversation(owner, type: :group, account_ids: [bob.id], title: 'Local room') }
  let(:room_uri) { Sharlayan::ChatFederation::Payload.room_uri(conversation) }
  let(:invite_object) do
    {
      'type' => 'Invite',
      'actor' => ActivityPub::TagManager.instance.uri_for(owner),
      'target' => bob.uri,
      'object' => Sharlayan::ChatFederation::Payload.room(conversation),
    }
  end

  before do
    Setting.chat_enabled = true
    Setting.chat_federation_enabled = true
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_federation_enabled = false
  end

  it 'adds the invitee on Accept' do
    accept = { 'type' => 'Accept', 'actor' => bob.uri, 'object' => invite_object }

    expect { ActivityPub::Activity.factory(accept, bob).perform }
      .to change { conversation.memberships.exists?(account: bob) }.from(false).to(true)
    expect(conversation.invitations.find_by(invitee_account: bob)).to be_accepted
  end

  it 'marks the invitation rejected on Reject' do
    reject = { 'type' => 'Reject', 'actor' => bob.uri, 'object' => invite_object }

    ActivityPub::Activity.factory(reject, bob).perform

    expect(conversation.invitations.find_by(invitee_account: bob)).to be_rejected
  end

  it 'removes the member on Remove' do
    service.receive_accept(bob, room_uri: room_uri)
    remove = {
      'type' => 'Remove',
      'actor' => bob.uri,
      'target' => room_uri,
      'object' => bob.uri,
    }

    expect { ActivityPub::Activity.factory(remove, bob).perform }
      .to change { conversation.memberships.exists?(account: bob) }.from(true).to(false)
  end
end
