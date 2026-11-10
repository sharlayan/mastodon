# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Invitations a group owner has sent' do
  include_context 'with an open chat policy'

  include_context 'with API authentication', oauth_scopes: 'read write'

  let(:service) { Sharlayan::ChatService.new }
  let(:member) { Fabricate(:user).account }
  let(:waiting) { Fabricate(:user).account }
  let(:nari) { Fabricate(:account, username: 'nari', domain: 'cherry.test', uri: 'https://cherry.test/users/nari', inbox_url: 'https://cherry.test/inbox', can_chat: true, chat_scope: 'everyone') }
  let(:room) { service.create_conversation(user.account, type: :group, title: 'Room', account_ids: [member.id, nari.id, waiting.id]) }
  let(:other_room) { service.create_conversation(user.account, type: :group, title: 'Other', account_ids: [waiting.id]) }

  before do
    Setting.chat_enabled = true
    Setting.chat_federation_enabled = true
    [member, waiting].each do |account|
      account.user.settings[:chat_allow_group_invites] = true
      account.user.save!
    end
    room
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_federation_enabled = false
  end

  def sent_to(conversation)
    get '/api/v1/chat/invitations', params: { direction: 'sent', conversation_id: conversation.id }, headers: headers
    response.parsed_body
  end

  describe 'GET /api/v1/chat/invitations with a conversation' do
    it 'lists who has not answered yet in that group only, with what the screen needs to tell the invited apart, and every group when none is named' do
      other_room

      expect(sent_to(room).map { |invitation| invitation.dig(:invitee, :id) }).to contain_exactly(member.id.to_s, nari.id.to_s, waiting.id.to_s)
      expect(response.parsed_body.find { |invitation| invitation.dig(:invitee, :id) == nari.id.to_s }).to include(
        id: be_a(String),
        state: 'pending',
        invitee: include(acct: 'nari@cherry.test', avatar: be_a(String))
      )
      expect(sent_to(other_room).map { |invitation| invitation.dig(:invitee, :id) }).to contain_exactly(waiting.id.to_s)

      get '/api/v1/chat/invitations', params: { direction: 'sent' }, headers: headers

      expect(response.parsed_body.size).to eq(4)
    end

    it 'drops someone who accepted, and shows nothing of the invitations of someone else' do
      service.accept_invitation(member, room.invitations.pending.find_by!(invitee_account: member))

      expect(sent_to(room).map { |invitation| invitation.dig(:invitee, :id) }).to_not include(member.id.to_s)

      token.update!(resource_owner_id: member.user.id)

      expect(sent_to(room)).to be_empty
    end
  end

  describe 'cancelling one from the members screen' do
    it 'is refused to someone who is not the owner, and otherwise removes it and leaves the group in place' do
      invitation = room.invitations.pending.find_by!(invitee_account: waiting)
      token.update!(resource_owner_id: member.user.id)

      delete "/api/v1/chat/invitations/#{invitation.id}", headers: headers

      expect(response).to_not have_http_status(200)
      expect(invitation.reload).to be_pending

      token.update!(resource_owner_id: user.id)
      delete "/api/v1/chat/invitations/#{invitation.id}", headers: headers

      expect(response).to have_http_status(200)
      expect(invitation.reload).to be_cancelled
      expect(ChatConversation.exists?(room.id)).to be(true)
      expect(sent_to(room).map { |item| item.dig(:invitee, :id) }).to_not include(waiting.id.to_s)
    end

    it 'tells the other server, in the form it already knows' do
      invitation = room.invitations.pending.find_by!(invitee_account: nari)
      ActivityPub::DeliveryWorker.clear

      delete "/api/v1/chat/invitations/#{invitation.id}", headers: headers

      delivered = ActivityPub::DeliveryWorker.jobs.map { |job| JSON.parse(job['args'].first) }
      expect(delivered.pluck('type')).to contain_exactly('Undo')
      expect(delivered.first.dig('object', 'type')).to eq('Invite')
    end
  end

  describe 'the owner’s open screen' do
    let(:published) { [] }

    before do
      allow(service.redis).to receive(:publish) { |channel, data| published << [channel, JSON.parse(data)] }
    end

    def told_owner
      published.select { |channel, event| channel == "timeline:#{user.account.id}" && event['event'] == 'chat.invitation_update' }
        .map { |_, event| JSON.parse(event['payload']) }
    end

    def activity(type)
      {
        'id' => "https://cherry.test/activities/#{type}", 'type' => type, 'actor' => nari.uri, 'published' => Time.now.utc.iso8601(3),
        'object' => { 'type' => 'Invite', 'actor' => ActivityPub::TagManager.instance.uri_for(user.account), 'object' => room.uri, 'target' => nari.uri }
      }
    end

    it 'hears when a same-server account rejects, and says nothing to anyone else' do
      service.reject_invitation(waiting, room.invitations.pending.find_by!(invitee_account: waiting))

      expect(told_owner).to contain_exactly(include('conversation_id' => room.id.to_s))
      expect(published.select { |channel, event| event['event'] == 'chat.invitation_update' && channel != "timeline:#{user.account.id}" }).to be_empty
    end

    it 'hears when a same-server account accepts' do
      service.accept_invitation(member, room.invitations.pending.find_by!(invitee_account: member))

      expect(told_owner).to contain_exactly(include('conversation_id' => room.id.to_s))
    end

    it 'hears when someone on another server rejects' do
      service.receive_reject(nari, room_uri: room.uri)

      expect(told_owner).to contain_exactly(include('conversation_id' => room.id.to_s))
    end

    it 'hears when someone on another server accepts, along with the new member list' do
      service.receive_accept(nari, room_uri: room.uri)

      expect(told_owner).to contain_exactly(include('conversation_id' => room.id.to_s))
      update = published.reverse.find { |channel, event| channel == "timeline:#{user.account.id}" && event['event'] == 'chat.conversation_update' }
      expect(JSON.parse(update.last['payload'])['accounts'].pluck('acct')).to include('nari@cherry.test')
    end

    it 'hears when the owner cancels in another tab' do
      service.cancel_invitation(user.account, room.invitations.pending.find_by!(invitee_account: waiting))

      expect(told_owner).to contain_exactly(include('conversation_id' => room.id.to_s))
    end
  end
end
