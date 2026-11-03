# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::ChatFederation::Payload do
  let(:owner) { Fabricate(:account) }
  let(:remote) { Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/bob') }
  let(:conversation) do
    ChatConversation.create!(conversation_type: :group, owner_account: owner, title: 'Room', description: 'desc').tap do |record|
      record.memberships.create!(account: owner, role: :owner)
      record.memberships.create!(account: remote)
    end
  end
  let(:message) do
    ChatMessage.create!(chat_conversation: conversation, account: owner, text: '<b>hi</b>')
  end

  it 'uses the web domain for object, activity and relative attachment URLs' do
    allow(Rails.configuration.x).to receive(:web_domain).and_return('social.example.com')
    file = double(url: '/system/media/test.png')
    attachment = double(id: 123, file: file, file_content_type: 'image/png', description: 'image')

    expect(described_class.note(message)['id']).to eq("https://social.example.com/chat/messages/#{message.id}")
    expect(described_class.room(conversation)['id']).to eq("https://social.example.com/chat/rooms/#{conversation.id}")
    expect(described_class.reaction(message, remote, '👍', reaction_id: 123)['id']).to start_with('https://social.example.com/chat/reactions/')
    expect(described_class.send(:document, attachment)['url']).to start_with('https://social.example.com/media_proxy/123/original')
    expect(described_class.send(:document, attachment)['url']).to include('token=')
  end

  it 'builds a canonical chat note' do
    note = described_class.note(message)

    expect(note['content']).to eq('&lt;b&gt;hi&lt;/b&gt;')
    expect(note['_misskey_content']).to eq('<b>hi</b>')
    expect(note['source']).to eq('content' => '<b>hi</b>', 'mediaType' => 'text/x.misskeymarkdown')
    expect(note['_misskey_talk']).to be(true)
    expect(note['to']).to include(remote.uri)
  end

  it 'identifies the room without treating it as a JSON-LD context document' do
    note = described_class.note(message)
    room_uri = "https://#{Rails.configuration.x.web_domain}/chat/rooms/#{conversation.id}"

    expect(note).to include('context' => room_uri, '_misskey_chatRoom' => room_uri)
    expect(note).to_not have_key('@context')
    canonical = Class.new { include JsonLdHelper }.new.canonicalize(described_class.create(message))
    expect(canonical).to include("<https://www.w3.org/ns/activitystreams#context> <#{room_uri}>")
    expect(canonical).to include('<https://misskey-hub.net/ns#_misskey_chatRoom>')
    compacted = Class.new { include JsonLdHelper }.new.compact(described_class.create(message))
    expect(compacted['object']).to include('context' => room_uri, '_misskey_chatRoom' => room_uri)
  end

  it 'preserves millisecond edit versions in updates and fetched notes' do
    message.update!(edited_at: Time.utc(2026, 11, 3, 0, 0, 0, 123_000))

    expect(described_class.update(message).dig('object', 'updated')).to eq('2026-11-03T00:00:00.123Z')
    expect(described_class.note(message)['updated']).to eq('2026-11-03T00:00:00.123Z')
  end

  it 'serializes every attachment of a note' do
    media = Array.new(2) { Fabricate(:media_attachment, account: owner) }
    media.each { |attachment| message.chat_message_media_attachments.create!(media_attachment: attachment) }

    expect(described_class.note(message.reload)['attachment'].size).to eq(2)
  end

  it 'builds a Delete Tombstone' do
    expect(described_class.delete(message)['object']).to include('type' => 'Tombstone', 'formerType' => 'Note')
  end

  it 'builds reaction and undo activities with the same persisted reaction ID' do
    react = described_class.reaction(message, remote, '👍', reaction_id: 123)
    undo = described_class.undo_reaction(message, remote, '👍', reaction_id: 123)

    expect(react['type']).to eq('EmojiReact')
    expect(react['id']).to start_with("#{Rails.configuration.x.use_https ? 'https' : 'http'}://#{Rails.configuration.x.local_domain}/chat/reactions/")
    expect(react['object']).to eq(described_class.message_uri(message))
    expect(undo['object']).to include('id' => react['id'], 'type' => 'EmojiReact')
  end

  it 'builds a Group object' do
    expect(described_class.room(conversation)).to include('type' => 'Group', 'name' => 'Room', 'summary' => 'desc')
  end

  it 'sends an empty summary when the room description is cleared' do
    conversation.update!(description: '')
    expect(described_class.room(conversation)).to include('summary' => '')
  end

  it 'makes relative media paths absolute' do
    file = double(url: '/system/media/test.png')
    attachment = double(id: 123, file: file, file_content_type: 'image/png', description: 'image', sensitive: false)

    expect(described_class.send(:document, attachment)['url'])
      .to start_with("#{Rails.configuration.x.use_https ? 'https' : 'http'}://#{Rails.configuration.x.local_domain}/media_proxy/123/original")
    expect(described_class.send(:document, attachment)['url']).to include('token=')
  end
end
