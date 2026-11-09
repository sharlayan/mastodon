# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Chat room member removal' do
  include_context 'with an open chat policy'

  include_context 'with API authentication', oauth_scopes: 'read write'

  let(:service) { Sharlayan::ChatService.new }
  let(:member) { Fabricate(:user) }
  let(:room) { service.create_conversation(user.account, type: :group, title: 'Room') }

  before do
    Setting.chat_enabled = true
    Setting.chat_federation_enabled = true
    Setting.misskey_compat_enabled = true
    room.memberships.create!(account: member.account)
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_federation_enabled = false
    Setting.misskey_compat_enabled = false
  end

  def remove_member(account = member.account, compat: false)
    if compat
      post '/api/chat/rooms/kick', params: { i: token.token, roomId: MisskeyCompat::MiId.encode(room.id), userId: MisskeyCompat::MiId.encode(account.id) }, as: :json
    else
      delete "/api/v1/chat/conversations/#{room.id}/members/#{account.id}", headers: headers
    end
  end

  [false, true].each do |compat|
    context(compat ? 'Misskey-compatible API' : 'native REST API') do
      it 'requires a write-capable token, then removes a member, retains history, and revokes read and write access' do
        message = service.create_message(member.account, room, text: 'history')
        token.update!(scopes: 'read')
        remove_member(compat: compat)

        expect(response).to have_http_status(403)
        expect(room.memberships.exists?(account: member.account)).to be(true)

        token.update!(scopes: 'read write')
        remove_member(compat: compat)

        expect(response).to have_http_status(compat ? 204 : 200)
        expect(room.memberships.exists?(account: member.account)).to be(false)
        expect(message.reload.text).to eq('history')

        token.update!(resource_owner_id: member.id)
        get "/api/v1/chat/conversations/#{room.id}/messages", headers: headers
        expect(response).to have_http_status(404)
        post "/api/v1/chat/conversations/#{room.id}/messages", params: { text: 'forbidden' }, headers: headers
        expect(response).to have_http_status(404)
      end

      it 'does not allow a member to remove the owner' do
        token.update!(resource_owner_id: member.id)
        remove_member(user.account, compat: compat)

        expect(response).to have_http_status(compat ? 400 : 403)
        expect(response.parsed_body.dig(:error, :code)).to eq('NO_SUCH_ROOM') if compat
        expect(room.memberships.count).to eq(2)
      end

      it 'does not allow the owner to remove themselves, nor silently succeed for a non-member' do
        remove_member(user.account, compat: compat)

        expect(response).to have_http_status(compat ? 400 : 403)
        expect(response.parsed_body.dig(:error, :code)).to eq('NO_SUCH_MEMBER') if compat
        expect(room.reload.memberships.count).to eq(2)

        remove_member(Fabricate(:user).account, compat: compat)

        expect(response).to have_http_status(compat ? 400 : 404)
        expect(response.parsed_body.dig(:error, :code)).to eq('NO_SUCH_MEMBER') if compat
        expect(room.memberships.count).to eq(2)
      end

      it 'allows moderation of an archived room' do
        service.archive(user.account, room, archived: true)
        remove_member(compat: compat)

        expect(response).to have_http_status(compat ? 204 : 200)
        expect(room.reload.archived_at).to be_present
        expect(room.memberships.exists?(account: member.account)).to be(false)
      end
    end
  end

  it 'does not remove a participant from a direct conversation' do
    direct = service.create_conversation(user.account, type: :direct, account_ids: [member.account.id])
    delete "/api/v1/chat/conversations/#{direct.id}/members/#{member.account.id}", headers: headers

    expect(response).to have_http_status(403)
    expect(direct.reload.memberships.count).to eq(2)
  end

  it 'notifies the removed local member and the remaining room members' do
    allow(service.redis).to receive(:publish)
    remove_member

    events = []
    expect(service.redis).to have_received(:publish).at_least(:once) do |channel, payload|
      events << [channel, JSON.parse(payload)]
    end
    expect(events).to include(["timeline:#{member.account.id}", include('event' => 'chat.conversation_delete', 'payload' => { conversation_id: room.id.to_s, reason: 'removed' }.to_json)])
    expect(events).to include(["timeline:#{user.account.id}", include('event' => 'chat.member_leave')])
  end

  it 'delivers the owner-signed Remove to the removed remote account and remaining peers' do
    remote = Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/member', inbox_url: 'https://remote.test/users/member/inbox', can_chat: true)
    peer = Fabricate(:account, domain: 'peer.test', uri: 'https://peer.test/users/peer', inbox_url: 'https://peer.test/users/peer/inbox')
    room.memberships.create!(account: remote)
    room.memberships.create!(account: peer)
    ActivityPub::DeliveryWorker.clear

    remove_member(remote)

    expect(response).to have_http_status(200)
    deliveries = ActivityPub::DeliveryWorker.jobs.pluck('args')
    expect(deliveries.pluck(2)).to contain_exactly(remote.inbox_url, peer.inbox_url)
    deliveries.each do |json, signer_id, _inbox|
      expect(signer_id).to eq(user.account.id)
      expect(JSON.parse(json)).to include('type' => 'Remove', 'actor' => ActivityPub::TagManager.instance.uri_for(user.account), 'object' => remote.uri, 'target' => room.uri)
    end
    expect(room.memberships.exists?(account: remote)).to be(false)

    get "/chat/rooms/#{room.id}", headers: nil, sign_with: remote
    expect(response).to have_http_status(404)
  end

  it 'requires a fresh invitation before a removed member can return' do
    remove_member
    expect(response).to have_http_status(200)
    expect(room.memberships.exists?(account: member.account)).to be(false)

    invitation = service.invite(user.account, room, member.account)
    service.accept_invitation(member.account, invitation)
    expect(room.memberships.exists?(account: member.account)).to be(true)
  end
end
