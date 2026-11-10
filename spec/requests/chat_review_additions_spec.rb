# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Chat review additions' do
  include_context 'with an open chat policy'

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

    it 'returns 404 on the public /media route, serves the checked proxy in REST payloads, and allows the expiring federated token without a user session' do
      get "/media/#{media.id}"
      expect(response).to have_http_status(404)

      payload = REST::ChatMessageSerializer.new(message, current_account: user.account).as_json
      expect(payload[:media_attachments].first[:url]).to include('/media_proxy/')
      expect(payload[:media_attachments].first[:preview_url]).to include('/media_proxy/')

      conversation.memberships.create!(account: Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/bob'))
      document = Sharlayan::ChatFederation::Payload.note(message, domain: 'remote.test')['attachment'].first
      expect(document['url']).to include('/media_proxy/')
      expect(document['url']).to include('token=')

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

    it 'shows administrators the copies of remote-owned rooms held here' do
      remote_room = service.receive_invite(owner, remote_member, room_uri: 'https://remote.test/chat/rooms/admin-review', title: 'Remote-owned room').chat_conversation
      sign_in admin

      get admin_chat_conversations_path
      expect(response.body).to include(admin_chat_conversation_path(remote_room))

      get admin_chat_conversation_path(remote_room)
      expect(response).to have_http_status(200)
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

    it 'returns 404 while chat is disabled and for a suspended signer' do
      message
      Setting.chat_enabled = false

      get "/chat/messages/#{message.id}", headers: nil, sign_with: remote
      expect(response).to have_http_status(404)

      Setting.chat_enabled = true
      remote.update!(suspended_at: Time.current)

      get "/chat/messages/#{message.id}", headers: nil, sign_with: remote
      expect(response).to have_http_status(404)
    end
  end

  describe 'custom emoji reactions' do
    let(:conversation) { service.create_conversation(user.account, type: :direct, account_ids: [other.account.id]) }
    let(:message) { service.create_message(other.account, conversation, text: 'react') }

    it 'exposes the local custom emoji image and accepts an unknown custom emoji from a remote account' do
      Fabricate(:custom_emoji, shortcode: 'blobcat')
      reaction = message.reactions.create!(account: user.account, reaction: ':blobcat:')

      expect(REST::ChatMessageReactionSerializer.new(reaction).as_json[:url]).to be_present
      expect(message.reactions.create!(account: remote, reaction: ':remote_emoji:')).to be_persisted
    end
  end
end
