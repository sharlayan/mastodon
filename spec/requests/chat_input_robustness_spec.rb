# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Chat input that is not a single id' do
  include_context 'with an open chat policy'

  include_context 'with API authentication', oauth_scopes: 'read write'

  let(:service) { Sharlayan::ChatService.new }
  let(:account) { user.account }
  let(:member) { Fabricate(:user).account }
  let(:room) { service.create_conversation(account, type: :group, title: 'Room') }

  before do
    Setting.chat_enabled = true
    Setting.chat_federation_enabled = true
    member.user.settings[:chat_allow_group_invites] = true
    member.user.save!
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_federation_enabled = false
  end

  def uploaded(count)
    Array.new(count) { Fabricate(:media_attachment, account: account, status: nil) }
  end

  describe 'attachment ids' do
    it 'keeps the given order when an id is written with a leading zero' do
      first, second = uploaded(2)

      message = service.create_message(account, room, text: 'hi', media_ids: ["0#{second.id}", first.id.to_s])

      expect(message.reload.media_attachments.map(&:id)).to eq([second.id, first.id])
    end

    it 'refuses an id that is not a number' do
      expect { service.create_message(account, room, text: 'hi', media_ids: ['abc']) }
        .to raise_error(Sharlayan::ChatService::Error, /not found/)
    end

    it 'sends a leading-zero id over the API instead of failing' do
      first, second = uploaded(2)

      post "/api/v1/chat/conversations/#{room.id}/messages", params: { text: 'hi', media_ids: ["0#{second.id}", first.id.to_s] }, headers: headers, as: :json

      expect(response).to have_http_status(200)
      expect(response.parsed_body['media_attachments'].pluck('id')).to eq([second.id.to_s, first.id.to_s])
    end
  end

  describe 'POST /api/v1/chat/conversations/:id/read' do
    it 'rejects a list of message ids' do
      message = service.create_message(account, room, text: 'hi')

      post "/api/v1/chat/conversations/#{room.id}/read", params: { message_id: [message.id] }, headers: headers, as: :json

      expect(response).to have_http_status(400)
    end
  end

  describe 'POST /api/v1/chat/conversations/:id/invitations' do
    it 'rejects a list of account ids' do
      post "/api/v1/chat/conversations/#{room.id}/invitations", params: { account_id: [member.id] }, headers: headers, as: :json

      expect(response).to have_http_status(400)
      expect(room.invitations).to be_empty
    end
  end

  describe 'paging with a list as the cursor' do
    it 'rejects it for conversations' do
      get '/api/v1/chat/conversations', params: { max_id: [room.id] }, headers: headers

      expect(response).to have_http_status(400)
    end

    it 'rejects it for messages' do
      get "/api/v1/chat/conversations/#{room.id}/messages", params: { max_id: ['1'] }, headers: headers

      expect(response).to have_http_status(400)
    end

    it 'rejects it for invitations' do
      get '/api/v1/chat/invitations', params: { max_id: ['1'] }, headers: headers

      expect(response).to have_http_status(400)
    end
  end

  describe 'starting a chat while federation is off' do
    let(:remote) { Fabricate(:account, username: 'bob', domain: 'remote.test', uri: 'https://remote.test/users/bob', inbox_url: 'https://remote.test/inbox', last_webfingered_at: 2.days.ago, can_chat: true, chat_scope: 'everyone') }

    it 'does not contact the remote server before refusing' do
      Setting.chat_federation_enabled = false
      fetcher = instance_double(ActivityPub::FetchRemoteAccountService, call: nil)
      allow(ActivityPub::FetchRemoteAccountService).to receive(:new).and_return(fetcher)

      expect { service.create_direct_message(account, remote, text: 'hi') }
        .to raise_error(Sharlayan::ChatService::Error, /federation is disabled/)
      expect(fetcher).to_not have_received(:call)
    end
  end
end
