# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Chat federation regressions' do
  let(:service) { Sharlayan::ChatService.new }
  let(:owner) { Fabricate(:user).account }
  let(:invitee) { Fabricate(:user).account }
  let(:remote) { Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/bob', inbox_url: 'https://remote.test/users/bob/inbox', can_chat: true, chat_scope: 'everyone') }
  let(:room) { service.create_conversation(owner, type: :group, title: 'Private room') }
  let(:remote_room_uri) { 'https://remote.test/chat/rooms/91' }
  let(:document) { { 'type' => 'Document', 'url' => 'https://remote.test/image.jpg', 'mediaType' => 'image/jpeg' } }

  before do
    Setting.chat_enabled = true
    Setting.chat_federation_enabled = true
    Setting.chat_soft_delete_enabled = false
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_federation_enabled = false
    Setting.chat_soft_delete_enabled = false
  end

  def perform(json, actor = remote)
    ActivityPub::Activity.factory(json, actor, delivered_to_account_id: owner.id).perform
  end

  def invite_json(uri = remote_room_uri, attribution = remote.uri)
    { 'type' => 'Invite', 'actor' => remote.uri,
      'target' => ActivityPub::TagManager.instance.uri_for(invitee),
      'object' => { 'id' => uri, 'type' => 'Group', 'name' => 'Remote room', 'attributedTo' => attribution } }
  end

  def note_json(uri = 'https://remote.test/chat/messages/91')
    { 'type' => 'Create', 'actor' => remote.uri, 'object' => {
      'id' => uri, 'type' => 'Note', 'attributedTo' => remote.uri,
      '_misskey_talk' => true, 'content' => 'hello',
      'to' => [ActivityPub::TagManager.instance.uri_for(owner)]
    } }
  end

  it 'rejects an invitation from a non-owner to an existing local room' do
    expect { perform(invite_json(room.uri)) }.to_not change(ChatInvitation, :count)
    expect(room.memberships.exists?(account: invitee)).to be false
  end

  it 'rejects a same-origin non-owner inviting someone to an existing mirror room' do
    invitation = service.receive_invite(owner, remote, room_uri: remote_room_uri, title: 'Remote room')
    attacker = Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/eve')
    json = invite_json(remote_room_uri, attacker.uri).merge('actor' => attacker.uri)

    expect { perform(json, attacker) }.to_not change(ChatInvitation, :count)
    expect(invitation.chat_conversation.reload.owner_account).to eq(remote)
  end

  it 'rejects an invitation attributed to someone other than the sender' do
    expect { perform(invite_json(remote_room_uri, 'https://other.test/users/eve')) }.to_not change(ChatConversation, :count)
  end

  it 'rejects an invitation for a room hosted by another origin' do
    expect { perform(invite_json('https://other.test/chat/rooms/1')) }.to_not change(ChatConversation, :count)
  end

  it 'receives a valid invitation from the remote room owner' do
    perform(invite_json)
    invitation = ChatInvitation.find_by!(invitee_account: invitee)
    expect(invitation.chat_conversation.owner_account).to eq(remote)
    expect(invitation).to be_pending
  end

  it 'does not expose any last message to a pending invitee or anonymous serializer' do
    service.create_message(owner, room, text: 'private text')
    invitation = service.invite(owner, room, invitee)

    expect(REST::ChatInvitationSerializer.new(invitation, current_account: invitee).as_json[:conversation][:last_message]).to be_nil
    expect(REST::ChatConversationSerializer.new(room).as_json[:last_message]).to be_nil
    expect(REST::ChatConversationSerializer.new(room, current_account: owner).as_json[:last_message][:content]).to eq('private text')
  end

  it 'keeps chat uploads attached and out of orphan cleanup' do
    media = Fabricate(:media_attachment, account: owner, created_at: 2.days.ago)
    service.create_message(owner, room, text: 'image', media_ids: [media.id])

    expect(MediaAttachment.attached).to include(media)
    expect(MediaAttachment.in_use).to include(media)
    expect(MediaAttachment.unattached).to_not include(media)
    Vacuum::MediaAttachmentsVacuum.new(nil).perform
    expect(MediaAttachment.exists?(media.id)).to be true
  end

  it 'accepts incoming attachment-only messages and persists their media' do
    message = service.receive_direct_message(owner, remote, uri: 'https://remote.test/chat/messages/92', text: nil, attachment: document)

    expect(message).to be_persisted
    expect(message.media_attachments.first.remote_url).to eq(document['url'])
    expect(message.chat_conversation.reload.last_message).to eq(message)
  end

  it 'receives an attachment-only Note without creating a public status' do
    json = note_json('https://remote.test/chat/messages/attachment-only')
    json['object'].delete('content')
    json['object']['attachment'] = [document]

    expect { perform(json) }.to change(ChatMessage, :count).by(1)
    expect(ChatMessage.find_by!(uri: json['object']['id']).media_attachments.first.remote_url).to eq(document['url'])
    expect(Status.where(uri: json['object']['id'])).to be_empty
  end

  it 'rolls back media created before an invalid incoming message is validated' do
    expect do
      expect do
        service.receive_direct_message(owner, remote, uri: 'https://remote.test/chat/messages/invalid', text: 'a' * 4_097, attachment: document)
      end.to raise_error(ActiveRecord::RecordInvalid)
    end.to_not change(MediaAttachment, :count)
    expect(ChatMessage.where(uri: 'https://remote.test/chat/messages/invalid')).to be_empty
  end

  it 'rolls back the message and media when incoming attachment validation fails' do
    allow(MediaAttachment).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(MediaAttachment.new))

    expect do
      expect do
        service.receive_direct_message(owner, remote, uri: 'https://remote.test/chat/messages/93', text: 'photo', attachment: document)
      end.to raise_error(ActiveRecord::RecordInvalid)
    end.to_not change(ChatMessage, :count)
    expect(MediaAttachment.where(remote_url: document['url'])).to be_empty
  end

  describe 'private media proxy' do
    let(:message) { service.receive_direct_message(owner, remote, uri: 'https://remote.test/chat/messages/94', text: 'photo', attachment: document) }
    let(:media) { message.media_attachments.first }

    before { stub_request(:get, document['url']).to_return(request_fixture('avatar.txt')) }

    it 'downloads and redirects media for a current member' do
      sign_in owner.user
      get "/media_proxy/#{media.id}/original"

      expect(response).to have_http_status(302)
      expect(media.reload.file).to be_present
    end

    it 'denies anonymous visitors' do
      get "/media_proxy/#{media.id}/original"
      expect(response).to have_http_status(404)
    end

    it 'denies authenticated nonmembers' do
      sign_in invitee.user
      get "/media_proxy/#{media.id}/original"
      expect(response).to have_http_status(404)
    end

    it 'denies former group members while retaining the message and media' do
      service.invite(owner, room, remote)
      service.receive_accept(remote, room_uri: room.uri)
      service.accept_invitation(invitee, service.invite(owner, room, invitee))
      group_message = service.receive_group_message(remote, room_uri: room.uri, uri: 'https://remote.test/chat/messages/former', text: 'photo', attachment: document)
      group_media = group_message.media_attachments.first
      service.leave(invitee, room)
      sign_in invitee.user

      get "/media_proxy/#{group_media.id}/original"

      expect(response).to have_http_status(404)
      expect(group_message.reload.media_attachments).to include(group_media)
      expect(room.reload.accounts).to include(owner, remote)
    end

    it 'denies pending group invitees' do
      service.invite(owner, room, remote)
      service.receive_accept(remote, room_uri: room.uri)
      service.invite(owner, room, invitee)
      group_message = service.receive_group_message(remote, room_uri: room.uri, uri: 'https://remote.test/chat/messages/pending', text: 'photo', attachment: document)
      sign_in invitee.user

      get "/media_proxy/#{group_message.media_attachments.first.id}/original"

      expect(response).to have_http_status(404)
    end

    it 'denies a hidden message attachment to the member who hid it' do
      hidden_media = Fabricate(:media_attachment, account: owner)
      conversation = service.create_conversation(owner, type: :direct, account_ids: [invitee.id])
      message = service.create_message(owner, conversation, text: 'photo', media_ids: [hidden_media.id])
      Setting.chat_soft_delete_enabled = true
      service.delete_message(owner, message)
      sign_in owner.user

      get "/media_proxy/#{hidden_media.id}/original"

      expect(message.reload).to be_hidden
      expect(response).to have_http_status(404)
    end
  end

  it 'announces a joining local member to existing remote room members' do
    service.invite(owner, room, remote)
    service.receive_accept(remote, room_uri: room.uri)
    invitation = service.invite(owner, room, invitee)

    expect { service.accept_invitation(invitee, invitation) }.to change(ActivityPub::DeliveryWorker.jobs, :size).by(1)
    job = ActivityPub::DeliveryWorker.jobs.last
    expect(job['args'][2]).to eq(remote.inbox_url)
    expect(JSON.parse(job['args'][0])).to include('type' => 'Add', 'object' => ActivityPub::TagManager.instance.uri_for(invitee))
  end

  it 'delivers cancellation directly to a pending remote invitee' do
    invitation = service.invite(owner, room, remote)

    expect { service.cancel_invitation(owner, invitation) }.to change(ActivityPub::DeliveryWorker.jobs, :size).by(1)
    expect(ActivityPub::DeliveryWorker.jobs.last['args'][2]).to eq(remote.inbox_url)
    expect(JSON.parse(ActivityPub::DeliveryWorker.jobs.last['args'][0])['type']).to eq('Undo')
  end

  describe 'incoming roster' do
    let(:conversation) { service.receive_invite(owner, remote, room_uri: remote_room_uri, title: 'Remote room').chat_conversation }

    it 'resolves canonical local actor URIs for Add' do
      perform('type' => 'Add', 'actor' => remote.uri, 'target' => conversation.uri, 'object' => ActivityPub::TagManager.instance.uri_for(invitee))
      expect(conversation.accounts).to include(invitee)
    end

    it 'fetches unknown actors for Add' do
      uri = 'https://new.test/users/alice'
      actor = { '@context' => 'https://www.w3.org/ns/activitystreams', 'id' => uri, 'type' => 'Person', 'preferredUsername' => 'alice', 'inbox' => 'https://new.test/users/alice/inbox' }
      webfinger = { subject: 'acct:alice@new.test', links: [{ rel: 'self', href: uri, type: 'application/activity+json' }] }
      stub_request(:get, uri).to_return(body: actor.to_json, headers: { 'Content-Type' => 'application/activity+json' })
      stub_request(:get, 'https://new.test/.well-known/webfinger?resource=acct:alice@new.test').to_return(body: webfinger.to_json, headers: { 'Content-Type' => 'application/jrd+json' })

      perform('type' => 'Add', 'actor' => remote.uri, 'target' => conversation.uri, 'object' => uri)
      expect(conversation.accounts.pluck(:uri)).to include(uri)
    end

    it 'does not fetch accounts requested by a non-owner' do
      conversation
      allow(ActivityPub::FetchRemoteAccountService).to receive(:new).and_call_original
      perform({ 'type' => 'Add', 'actor' => remote.uri, 'target' => conversation.uri, 'object' => 'https://new.test/users/alice' }, Fabricate(:account, domain: 'other.test'))
      expect(ActivityPub::FetchRemoteAccountService).to_not have_received(:new)
    end
  end

  describe 'Undo Invite' do
    let(:invitation) { service.receive_invite(invitee, remote, room_uri: remote_room_uri, title: 'Remote room') }
    let(:undo) { { 'type' => 'Undo', 'actor' => remote.uri, 'object' => invite_json } }

    it 'cancels an invitation when its authenticated owner undoes it' do
      invitation
      perform(undo)
      expect(invitation.reload).to be_cancelled
    end

    it 'does not let another actor cancel an invitation' do
      invitation
      perform(undo, Fabricate(:account, domain: 'other.test'))
      expect(invitation.reload).to be_pending
    end

    it 'does not let a mismatched embedded actor cancel an invitation' do
      invitation
      undo['object']['actor'] = 'https://other.test/users/eve'
      perform(undo)
      expect(invitation.reload).to be_pending
    end

    it 'does not cancel an already accepted invitation' do
      service.accept_invitation(invitee, invitation)
      perform(undo)
      expect(invitation.reload).to be_accepted
    end
  end

  %i(chat_enabled chat_federation_enabled).each do |setting|
    context "when #{setting} is disabled" do
      it 'consumes chat Creates without creating messages or public statuses' do
        json = note_json
        Setting.public_send(:"#{setting}=", false)
        expect { perform(json) }.to_not change(ChatMessage, :count)
        expect(Status.where(uri: json['object']['id'])).to be_empty
      end

      it 'does not accept invitations' do
        json = invite_json
        Setting.public_send(:"#{setting}=", false)
        expect { perform(json) }.to_not change(ChatInvitation, :count)
      end

      it 'does not change room membership, metadata or invitations' do
        invitation = service.receive_invite(invitee, remote, room_uri: remote_room_uri, title: 'Remote room')
        conversation = invitation.chat_conversation
        pending = service.invite(owner, room, remote)
        Setting.public_send(:"#{setting}=", false)

        perform('type' => 'Add', 'actor' => remote.uri, 'target' => conversation.uri, 'object' => ActivityPub::TagManager.instance.uri_for(owner))
        perform('type' => 'Remove', 'actor' => remote.uri, 'target' => conversation.uri, 'object' => remote.uri)
        perform('type' => 'Update', 'actor' => remote.uri, 'object' => invite_json['object'].merge('name' => 'Changed'))
        perform('type' => 'Undo', 'actor' => remote.uri, 'object' => invite_json)
        perform('type' => 'Accept', 'actor' => remote.uri, 'object' => Sharlayan::ChatFederation::Payload.invite(room, remote))
        expect(pending.reload).to be_pending
        perform('type' => 'Reject', 'actor' => remote.uri, 'object' => Sharlayan::ChatFederation::Payload.invite(room, remote))
        perform('type' => 'Delete', 'actor' => remote.uri, 'object' => conversation.uri)

        expect(conversation.reload.title).to eq('Remote room')
        expect(conversation.accounts).to contain_exactly(remote)
        expect(invitation.reload).to be_pending
        expect(pending.reload).to be_pending
        expect(room.accounts).to contain_exactly(owner)
      end

      it 'does not mutate messages through Update, Delete, reaction or Undo' do
        message = service.receive_direct_message(owner, remote, uri: 'https://remote.test/chat/messages/95', text: 'private')
        conversation = message.chat_conversation
        local_message = service.create_message(owner, conversation, text: 'react')
        service.react_remote(remote, local_message, '👍')
        update = note_json(message.uri).merge('type' => 'Update')
        reaction = { 'type' => 'EmojiReact', 'actor' => remote.uri, 'object' => local_message.uri, 'content' => '👍' }
        Setting.public_send(:"#{setting}=", false)

        perform(update)
        perform('type' => 'Delete', 'actor' => remote.uri, 'object' => message.uri)
        perform(reaction.merge('content' => '😃'))
        perform('type' => 'Undo', 'actor' => remote.uri, 'object' => reaction)

        expect(message.reload.text).to eq('private')
        expect(message).to_not be_deleted
        expect(local_message.reactions.pluck(:reaction)).to eq(['👍'])
      end
    end
  end

  it 'does not let a foreign actor tombstone another actors future message' do
    uri = 'https://remote.test/chat/messages/96'
    perform({ 'type' => 'Delete', 'object' => uri }, Fabricate(:account, domain: 'attacker.test', uri: 'https://attacker.test/users/eve'))
    expect { perform(note_json(uri)) }.to change(ChatMessage, :count).by(1)
  end

  it 'does not let a same-origin actor tombstone another actors future message' do
    uri = 'https://remote.test/chat/messages/97'
    perform({ 'type' => 'Delete', 'object' => uri }, Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/eve'))
    expect { perform(note_json(uri)) }.to change(ChatMessage, :count).by(1)
  end

  it 'honors an authenticated senders own pre-arrival deletion' do
    uri = "https://remote.test/chat/messages/#{SecureRandom.hex}"
    perform('type' => 'Delete', 'actor' => remote.uri, 'object' => uri)
    expect { perform(note_json(uri)) }.to_not change(ChatMessage, :count)
  end

  it 'emits a full serialized reaction for remote reaction stream events' do
    conversation = service.create_conversation(owner, type: :direct, account_ids: [remote.id])
    message = service.create_message(owner, conversation, text: 'react to this')
    allow(service).to receive(:broadcast)
    service.react_remote(remote, message, '👍')
    reaction = message.reactions.find_by!(account: remote)
    expect(service).to have_received(:broadcast).with(conversation, 'chat.reaction', hash_including(created_at: reaction.created_at, message_id: message.id.to_s, reaction: '👍', account: hash_including(id: remote.id.to_s, acct: remote.acct)))
  end
end
