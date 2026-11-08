# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Chat message deletion notice' do
  include_context 'with API authentication', oauth_scopes: 'read write'

  let!(:user) { Fabricate(:user, account_attributes: { username: 'alice' }) }
  let(:other) { Fabricate(:user, account_attributes: { username: 'bob' }).account }
  let(:conversation) do
    ChatConversation.create!(conversation_type: :direct, direct_key: [user.account_id, other.id].sort.join(':')).tap do |record|
      record.memberships.create!([{ account: user.account }, { account: other }])
    end
  end
  let(:message) { conversation.messages.create!(account: user.account, text: 'hello', created_at: age.ago) }
  let(:age) { 1.hour }

  around { |example| ClimateControl.modify(OC_ROLEPLAY_OPTION: 'false') { example.run } }

  before do
    Setting.chat_enabled = true
    Setting.chat_soft_delete_enabled = false
    Setting.chat_delete_window_hours = 24
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_soft_delete_enabled = false
    Setting.chat_delete_window_hours = 24
  end

  def deletes_for_everyone
    get "/api/v1/chat/messages/#{message.id}", headers: headers
    response.parsed_body[:deletes_for_everyone]
  end

  it 'reports that a recent message is deleted for everyone' do
    expect(deletes_for_everyone).to be(true)
  end

  context 'when the delete window has passed' do
    let(:age) { 25.hours }

    it 'reports that the message is only hidden' do
      expect(deletes_for_everyone).to be(false)
    end
  end

  it 'reports that soft delete only hides the message' do
    Setting.chat_soft_delete_enabled = true

    expect(deletes_for_everyone).to be(false)
  end

  it 'reports that roleplay mode only hides the message' do
    ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') { expect(deletes_for_everyone).to be(false) }
  end

  it 'decides deletion by the same rule it reports' do
    expect(message.within_delete_window?).to be(true)

    Sharlayan::ChatService.new.delete_message(user.account, message)

    expect(message.reload).to be_deleted
  end

  context 'when the same rule says the window has passed' do
    let(:age) { 25.hours }

    it 'hides the message' do
      expect(message.within_delete_window?).to be(false)

      Sharlayan::ChatService.new.delete_message(user.account, message)

      expect(message.reload).to be_hidden
    end
  end
end
