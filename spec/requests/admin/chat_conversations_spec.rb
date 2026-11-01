# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin Chat conversations' do
  let!(:first) { Fabricate(:user) }
  let!(:second) { Fabricate(:user) }
  let!(:conversation) { Sharlayan::ChatService.new.create_conversation(first.account, type: :direct, account_ids: [second.account.id]) }

  before do
    Setting.chat_enabled = true
    sign_in Fabricate(:admin_user)
  end

  after { Setting.chat_enabled = false }

  it 'lists and inspects chat conversations' do
    Sharlayan::ChatService.new.create_message(first.account, conversation, text: 'moderation-visible')

    get admin_chat_conversations_path
    expect(response).to have_http_status(200)

    get admin_chat_conversation_path(conversation)
    expect(response).to have_http_status(200)
    expect(response.body).to include('moderation-visible')
  end

  it 'deletes a conversation and all messages' do
    message = Sharlayan::ChatService.new.create_message(first.account, conversation, text: 'delete-me')

    delete admin_chat_conversation_path(conversation)

    expect(response).to redirect_to(admin_chat_conversations_path)
    expect(ChatConversation).to_not exist(conversation.id)
    expect(ChatMessage).to_not exist(message.id)
  end

  it 'keeps moderation access available while user chat is disabled' do
    Setting.chat_enabled = false

    get admin_chat_conversation_path(conversation)

    expect(response).to have_http_status(200)
  end

  it 'allows the management timeline permission to inspect local chat in roleplay mode' do
    role = Fabricate(:user_role, extra_permissions: UserRole::EXTRA_FLAGS[:view_admin_timeline])
    viewer = Fabricate(:user, role: role)
    sign_in viewer

    ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') do
      get admin_chat_conversation_path(conversation)
    end

    expect(response).to have_http_status(200)
  end

  it 'does not let the management timeline permission destroy chat conversations' do
    role = Fabricate(:user_role, extra_permissions: UserRole::EXTRA_FLAGS[:view_admin_timeline])
    viewer = Fabricate(:user, role: role)
    sign_in viewer

    ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') do
      delete admin_chat_conversation_path(conversation)
    end

    expect(response).to have_http_status(403)
    expect(ChatConversation).to exist(conversation.id)
  end
end
