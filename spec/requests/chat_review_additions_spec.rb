# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Chat review additions' do
  let(:service) { Sharlayan::ChatService.new }
  let(:user) { Fabricate(:user) }
  let(:other) { Fabricate(:user) }
  let(:remote) do
    Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/review', inbox_url: 'https://remote.test/users/review/inbox', can_chat: true, chat_scope: 'everyone')
  end

  before do
    Setting.chat_enabled = true
    Setting.chat_federation_enabled = true
    Setting.chat_soft_delete_enabled = false
    Setting.chat_max_attachments = 4
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_federation_enabled = false
    Setting.chat_soft_delete_enabled = false
    Setting.chat_max_attachments = 1
  end

  describe 'chat media privacy' do
    let(:conversation) { service.create_conversation(user.account, type: :direct, account_ids: [other.account.id]) }
    let(:media) { Fabricate(:media_attachment, account: user.account, status: nil) }
    let!(:message) { service.create_message(user.account, conversation, text: nil, media_ids: [media.id]) }

    it 'returns 404 for chat media on the public /media route' do
      get "/media/#{media.id}"

      expect(response).to have_http_status(404)
    end

    it 'serves chat media through the checked proxy in REST payloads' do
      payload = REST::ChatMessageSerializer.new(message, current_account: user.account).as_json

      expect(payload[:media_attachments].first[:url]).to include('/media_proxy/')
      expect(payload[:media_attachments].first[:preview_url]).to include('/media_proxy/')
    end

    it 'uses an expiring proxy token in ActivityPub documents' do
      document = Sharlayan::ChatFederation::Payload.note(message)['attachment'].first

      expect(document['url']).to include('/media_proxy/')
      expect(document['url']).to include('token=')
    end

    it 'allows the federated media token without a user session' do
      document = Sharlayan::ChatFederation::Payload.note(message)['attachment'].first
      uri = URI.parse(document['url'])

      get "#{uri.path}?#{uri.query}"

      expect(response).to have_http_status(:redirect)
    end

    it 'destroys chat media when the message is hard-deleted' do
      service.delete_message(user.account, message)

      expect(MediaAttachment.exists?(media.id)).to be(false)
    end
  end

  describe 'admin moderation' do
    let!(:admin) { Fabricate(:admin_user) }
    let!(:owner) { Fabricate(:user).account }
    let!(:remote_member) do
      Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/member', inbox_url: 'https://remote.test/users/member/inbox')
    end
    let!(:conversation) do
      service.create_conversation(owner, type: :group, title: 'Moderated group').tap do |record|
        record.memberships.create!(account: remote_member)
      end
    end

    it 'federates the room deletion and removes it locally' do
      sign_in admin

      expect do
        delete "/admin/chat/conversations/#{conversation.id}"
      end.to change(ActivityPub::DeliveryWorker.jobs, :size).by(1)
      expect(ChatConversation).to_not exist(conversation.id)
    end

    it 'keeps remote-owned rooms out of the admin index' do
      remote_room = service.receive_invite(owner, remote_member, room_uri: 'https://remote.test/chat/rooms/admin-review', title: 'Remote-owned room').chat_conversation
      sign_in admin

      get admin_chat_conversations_path
      expect(response.body).to_not include('Remote-owned room')

      get admin_chat_conversation_path(remote_room)
      expect(response).to have_http_status(403)
    end

    it 'does not let the roleplay timeline permission reach unrelated admin pages' do
      role = Fabricate(:user_role, extra_permissions: UserRole::EXTRA_FLAGS[:view_admin_timeline])
      viewer = Fabricate(:user, role: role)
      sign_in viewer

      ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') do
        get '/admin/dashboard'
      end

      expect(response).to have_http_status(403)
    end
  end

  describe 'ActivityPub access' do
    let(:conversation) do
      service.create_conversation(user.account, type: :group, account_ids: [remote.id], title: 'Remote room').tap do |record|
        record.memberships.create!(account: remote)
      end
    end
    let(:message) { service.create_message(user.account, conversation, text: 'secret') }

    it 'returns 404 while chat is disabled' do
      Setting.chat_enabled = false

      get "/chat/messages/#{message.id}", headers: nil, sign_with: remote

      expect(response).to have_http_status(404)
    end

    it 'returns 404 for a suspended signer' do
      message
      remote.update!(suspended_at: Time.current)

      get "/chat/messages/#{message.id}", headers: nil, sign_with: remote

      expect(response).to have_http_status(404)
    end
  end

  describe 'custom emoji reactions' do
    let(:conversation) { service.create_conversation(user.account, type: :direct, account_ids: [other.account.id]) }
    let(:message) { service.create_message(other.account, conversation, text: 'react') }

    it 'exposes the local custom emoji image' do
      Fabricate(:custom_emoji, shortcode: 'blobcat')
      reaction = message.reactions.create!(account: user.account, reaction: ':blobcat:')

      payload = REST::ChatMessageReactionSerializer.new(reaction).as_json

      expect(payload[:url]).to be_present
    end

    it 'accepts an unknown custom emoji from a remote account' do
      reaction = message.reactions.create!(account: remote, reaction: ':remote_emoji:')

      expect(reaction).to be_persisted
    end
  end

  describe 'reaction visibility' do
    include_context 'with API authentication', oauth_scopes: 'read write'

    it 'returns 404 for a reaction on a message the account cannot see' do
      hidden = service.create_conversation(other.account, type: :direct, account_ids: [Fabricate(:user).account.id])
      message = service.create_message(other.account, hidden, text: 'private')

      post "/api/v1/chat/messages/#{message.id}/reactions", params: { reaction: '👍' }, headers: headers

      expect(response).to have_http_status(404)
    end
  end
end
