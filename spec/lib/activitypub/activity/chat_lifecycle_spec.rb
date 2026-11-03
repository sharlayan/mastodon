# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ActivityPub chat message lifecycle', type: :model do
  let(:alice) { Fabricate(:user).account }
  let(:bob) { Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/bob', inbox_url: 'https://remote.test/users/bob/inbox', can_chat: true, chat_scope: 'everyone') }
  let(:service) { Sharlayan::ChatService.new }
  let(:message) { service.receive_direct_message(alice, bob, uri: 'https://remote.test/chat/messages/1', text: 'hello') }

  before do
    Setting.chat_enabled = true
    Setting.chat_federation_enabled = true
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_federation_enabled = false
  end

  it 'updates an authored message' do
    update = {
      'type' => 'Update',
      'actor' => bob.uri,
      'object' => {
        'id' => message.uri,
        'type' => 'Note',
        'attributedTo' => bob.uri,
        '_misskey_talk' => true,
        '_misskey_content' => 'edited',
        'updated' => '2026-11-02T00:02:00Z',
      },
    }

    expect { ActivityPub::Activity.factory(update, bob).perform }
      .to change { message.reload.text }.from('hello').to('edited')
    expect(message.edited_at).to be_present
  end

  it 'soft-deletes an authored message' do
    delete = {
      'type' => 'Delete',
      'actor' => bob.uri,
      'object' => { 'id' => message.uri, 'type' => 'Tombstone', 'formerType' => 'Note' },
    }

    ActivityPub::Activity.factory(delete, bob).perform

    expect(message.reload.deleted_at).to be_present
  end

  it 'creates and removes a chat reaction from another member' do
    conversation = service.create_conversation(alice, type: :direct, account_ids: [bob.id])
    local_message = service.create_message(alice, conversation, text: 'hello')
    react = {
      'type' => 'EmojiReact',
      'actor' => bob.uri,
      'object' => local_message.uri,
      'content' => '👍',
    }
    undo = {
      'type' => 'Undo',
      'actor' => bob.uri,
      'object' => react,
    }

    expect { ActivityPub::Activity.factory(react, bob).perform }
      .to change { local_message.reactions.count }.by(1)
    expect { ActivityPub::Activity.factory(undo, bob).perform }
      .to change { local_message.reactions.count }.by(-1)
  end
end
