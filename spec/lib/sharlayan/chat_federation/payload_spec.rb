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
    attachment = double(file: file, file_content_type: 'image/png', description: 'image')

    expect(described_class.note(message)['id']).to eq("https://social.example.com/chat/messages/#{message.id}")
    expect(described_class.room(conversation)['id']).to eq("https://social.example.com/chat/rooms/#{conversation.id}")
    expect(described_class.reaction(message, remote, '👍')['id']).to start_with('https://social.example.com/chat/reactions/')
    expect(described_class.send(:document, attachment)['url']).to eq('https://social.example.com/system/media/test.png')
  end

  it 'builds a canonical chat note' do
    note = described_class.note(message)

    expect(note['content']).to eq('&lt;b&gt;hi&lt;/b&gt;')
    expect(note['_misskey_content']).to eq('<b>hi</b>')
    expect(note['source']).to eq('content' => '<b>hi</b>', 'mediaType' => 'text/x.misskeymarkdown')
    expect(note['_misskey_talk']).to be(true)
    expect(note['to']).to include(remote.uri)
  end

  it 'uses the room URI as @context for a group note' do
    expect(described_class.note(message)['@context']).to eq(described_class.room_uri(conversation))
  end

  it 'serializes every attachment of a note' do
    media = Array.new(2) { Fabricate(:media_attachment, account: owner) }
    media.each { |attachment| message.chat_message_media_attachments.create!(media_attachment: attachment) }

    expect(described_class.note(message.reload)['attachment'].size).to eq(2)
  end

  it 'builds a Delete Tombstone' do
    expect(described_class.delete(message)['object']).to include('type' => 'Tombstone', 'formerType' => 'Note')
  end

  it 'builds reaction and undo activities with deterministic ids' do
    react = described_class.reaction(message, remote, '👍')
    undo = described_class.undo_reaction(message, remote, '👍')

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
    attachment = double(file: file, file_content_type: 'image/png', description: 'image', sensitive: false)

    expect(described_class.send(:document, attachment)['url'])
      .to eq("#{Rails.configuration.x.use_https ? 'https' : 'http'}://#{Rails.configuration.x.local_domain}/system/media/test.png")
  end
end
