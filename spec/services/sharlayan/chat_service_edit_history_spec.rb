# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::ChatService do
  subject(:service) { described_class.new }

  let(:owner) { Fabricate(:user).account }
  let(:remote) { Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/bob', inbox_url: 'https://remote.test/users/bob/inbox') }
  let(:room) do
    ChatConversation.create!(conversation_type: :group, owner_account: owner, title: 'Room').tap do |record|
      record.memberships.create!(account: owner, role: :owner)
      record.memberships.create!(account: remote)
    end
  end
  let(:message) { room.messages.create!(account: owner, text: 'original') }
  let(:remote_message) { room.messages.create!(account: remote, text: 'original', uri: 'https://remote.test/chat/messages/1') }

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

  context 'when the server keeps deleted messages' do
    before { Setting.chat_soft_delete_enabled = true }

    it 'keeps what a message said before an edit' do
      service.update_message(owner, message, text: 'first edit')
      service.update_message(owner, message, text: 'second edit')

      expect(message.reload.text).to eq('second edit')
      expect(message.edits.order(:id).pluck(:text)).to eq(['original', 'first edit'])
    end

    it 'has nothing to keep when the text stays the same' do
      service.update_message(owner, message, text: 'original')

      expect(message.edits).to be_empty
    end

    it 'keeps what a remote message said before an edit' do
      service.update_remote_message(remote, remote_message, text: 'changed', edited_at: 1.minute.from_now)

      expect(remote_message.edits.pluck(:text)).to eq(['original'])
    end

    it 'does not keep it when an older edit is ignored' do
      remote_message.update!(edited_at: 1.minute.from_now)

      service.update_remote_message(remote, remote_message, text: 'stale', edited_at: 1.hour.ago)

      expect(remote_message.reload.text).to eq('original')
      expect(remote_message.edits).to be_empty
    end

    it 'still has the earlier text after the sender hides the message' do
      service.update_message(owner, message, text: 'covered up')
      service.delete_message(owner, message)

      expect(message.reload).to be_hidden
      expect(message.edits.pluck(:text)).to eq(['original'])
    end
  end

  context 'when the server is in roleplay mode' do
    around { |example| ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') { example.run } }

    it 'keeps what a message said before an edit' do
      service.update_message(owner, message, text: 'changed')

      expect(message.edits.pluck(:text)).to eq(['original'])
    end
  end

  context 'when the server does not keep deleted messages' do
    it 'keeps nothing of the edits' do
      service.update_message(owner, message, text: 'changed')

      expect(message.edits).to be_empty
    end
  end

  it 'loses the edits with the message when it is deleted for everyone' do
    Setting.chat_soft_delete_enabled = true
    service.update_remote_message(remote, remote_message, text: 'changed', edited_at: 1.minute.from_now)

    service.delete_remote_message(remote, remote_message)

    expect(remote_message.reload.text).to be_nil
    expect(remote_message.edits).to be_empty
  end

  describe 'editing after the delete window' do
    let(:old_message) { room.messages.create!(account: owner, text: 'original', created_at: 25.hours.ago) }

    it 'is refused' do
      expect { service.update_message(owner, old_message, text: 'changed') }.to raise_error(described_class::Error, /no longer be edited/)

      expect(old_message.reload.text).to eq('original')
    end

    it 'is refused even when the edits would be kept' do
      Setting.chat_soft_delete_enabled = true

      expect { service.update_message(owner, old_message, text: 'changed') }.to raise_error(described_class::Error, /no longer be edited/)
    end

    it 'is refused for every message when the window is zero' do
      Setting.chat_delete_window_hours = 0

      expect { service.update_message(owner, message, text: 'changed') }.to raise_error(described_class::Error, /no longer be edited/)
    end

    it 'is up to the author for a remote message, as their server sets the window' do
      old_remote = room.messages.create!(account: remote, text: 'original', uri: 'https://remote.test/chat/messages/2', created_at: 25.hours.ago)

      service.update_remote_message(remote, old_remote, text: 'changed', edited_at: Time.current)

      expect(old_remote.reload.text).to eq('changed')
    end
  end

  describe 'the API' do
    let(:serialized) { REST::ChatMessageSerializer.new(message, current_account: owner).as_json }

    it 'says a message can be edited inside the window' do
      expect(serialized[:editable]).to be(true)
    end

    it 'says it cannot after the window' do
      message.update!(created_at: 25.hours.ago)

      expect(serialized[:editable]).to be(false)
    end

    it 'says it cannot once it is deleted' do
      message.update!(text: nil, deleted_at: Time.current)

      expect(serialized[:editable]).to be(false)
    end
  end
end
