# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin Chat conversations' do
  include_context 'with an open chat policy'

  let!(:first) { Fabricate(:user) }
  let!(:second) { Fabricate(:user) }
  let!(:conversation) { Sharlayan::ChatService.new.create_conversation(first.account, type: :direct, account_ids: [second.account.id]) }

  before do
    Setting.chat_enabled = true
    sign_in Fabricate(:admin_user)
  end

  after { Setting.chat_enabled = false }

  it 'lists and inspects chat conversations, with what a message said before its edits, also while user chat is disabled' do
    message = Sharlayan::ChatService.new.create_message(first.account, conversation, text: 'moderation-visible')
    message.edits.create!(text: 'the earlier text')

    get admin_chat_conversations_path
    expect(response).to have_http_status(200)

    get admin_chat_conversation_path(conversation)
    expect(response).to have_http_status(200)
    expect(response.body).to include('moderation-visible', 'the earlier text')

    Setting.chat_enabled = false
    get admin_chat_conversation_path(conversation)
    expect(response).to have_http_status(200)
  end

  it 'lets the management timeline permission inspect local chat in roleplay mode, but not destroy it' do
    role = Fabricate(:user_role, extra_permissions: UserRole::EXTRA_FLAGS[:view_admin_timeline])
    sign_in Fabricate(:user, role: role)

    ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') do
      get admin_chat_conversation_path(conversation)
      expect(response).to have_http_status(200)

      delete admin_chat_conversation_path(conversation)
    end

    expect(response).to have_http_status(403)
    expect(ChatConversation).to exist(conversation.id)
  end

  it 'deletes a conversation and all messages, and records the deletion in the audit log' do
    admin = Fabricate(:admin_user)
    sign_in admin
    message = Sharlayan::ChatService.new.create_message(first.account, conversation, text: 'delete-me')

    delete admin_chat_conversation_path(conversation)

    expect(response).to redirect_to(admin_chat_conversations_path)
    expect(ChatConversation).to_not exist(conversation.id)
    expect(ChatMessage).to_not exist(message.id)
    log = Admin::ActionLog.last
    expect(log).to have_attributes(account_id: admin.account_id, action: :destroy, target_type: 'ChatConversation', target_id: conversation.id)

    get admin_action_logs_path

    expect(response).to have_http_status(200)
    expect(response.body).to include("deleted chat conversation <span class=\"target\">##{conversation.id}</span>")
  end

  it 'lists conversations without messages after those with messages' do
    empty = Sharlayan::ChatService.new.create_conversation(first.account, type: :group, title: 'Quiet room')
    Sharlayan::ChatService.new.create_message(first.account, conversation, text: 'hello')

    get admin_chat_conversations_path

    expect(response.body.index(admin_chat_conversation_path(conversation))).to be < response.body.index(admin_chat_conversation_path(empty))
  end

  describe 'a copy of a room owned by another server' do
    let(:service) { Sharlayan::ChatService.new }
    let(:remote_owner) do
      Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/owner', inbox_url: 'https://remote.test/users/owner/inbox', can_chat: true, chat_scope: 'everyone')
    end
    let(:room_uri) { 'https://remote.test/chat/rooms/copy' }
    let(:copy) do
      service.receive_invite(first.account, remote_owner, room_uri: room_uri, title: 'Remote room').tap { |invitation| service.accept_invitation(first.account, invitation) }.chat_conversation
    end

    before do
      Setting.chat_federation_enabled = true
      first.settings[:chat_allow_group_invites] = true
      first.save!
      copy
    end

    after { Setting.chat_federation_enabled = false }

    it 'is listed and can be inspected, and is closed on this server with its owner told' do
      get admin_chat_conversations_path
      expect(response.body).to include(admin_chat_conversation_path(copy))

      get admin_chat_conversation_path(copy)
      expect(response).to have_http_status(200)
      expect(response.body).to include('remote.test')

      expect { delete admin_chat_conversation_path(copy) }.to change(ActivityPub::DeliveryWorker.jobs, :size).by(1)

      expect(ChatConversation).to_not exist(copy.id)
      expect(service.room_closed_here?(room_uri)).to be(true)
    end
  end

  describe 'the roleplay audit permission' do
    let(:remote) do
      Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/bob', inbox_url: 'https://remote.test/users/bob/inbox', can_chat: true, chat_scope: 'everyone')
    end
    let(:with_remote) { ChatConversation.create!(conversation_type: :direct, direct_key: [first.account_id, remote.id].sort.join(':')).tap { |record| record.memberships.create!([{ account: first.account }, { account: remote }]) } }

    around { |example| ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') { example.run } }

    before do
      role = Fabricate(:user_role, extra_permissions: UserRole::EXTRA_FLAGS[:view_admin_timeline])
      sign_in Fabricate(:user, role: role)
    end

    it 'lists only conversations between local accounts and does not reach a direct conversation with a remote account' do
      with_remote

      get admin_chat_conversations_path

      expect(response.body).to include(admin_chat_conversation_path(conversation))
      expect(response.body).to_not include(admin_chat_conversation_path(with_remote))

      get admin_chat_conversation_path(with_remote)

      expect(response).to have_http_status(403)
    end
  end
end
