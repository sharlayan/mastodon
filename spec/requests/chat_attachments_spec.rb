# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Chat message attachments' do
  let(:user) { Fabricate(:user) }
  let(:account) { user.account }
  let(:other) { Fabricate(:user) }
  let(:service) { Sharlayan::ChatService.new }
  let(:conversation) { service.create_conversation(account, type: :group, title: 'Room') }

  def uploaded(count)
    Array.new(count) { Fabricate(:media_attachment, account: account, status: nil) }
  end

  before do
    Setting.chat_enabled = true
    Setting.chat_federation_enabled = true
    other.settings[:chat_policy] = 'everyone'
    other.save!
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_federation_enabled = false
  end

  describe 'sending' do
    it 'keeps the attachments in the order they were given, also in every attachment of a Note' do
      first, second, third = uploaded(3)

      message = service.create_message(account, conversation, text: 'hi', media_ids: [third.id, first.id, second.id])

      expect(message.reload.media_attachments.map(&:id)).to eq([third.id, first.id, second.id])
      expect(ChatMessage.includes(:media_attachments).find(message.id).media_attachments.map(&:id)).to eq([third.id, first.id, second.id])
      expect(Sharlayan::ChatFederation::Payload.note(message)['attachment'].pluck('url'))
        .to match([third, first, second].map { |media| a_string_including("/media_proxy/#{media.id}/") })
    end

    it 'allows four attachments by default and refuses a fifth' do
      expect(Setting.chat_max_attachments).to eq(4)
      expect { service.create_message(account, conversation, text: 'hi', media_ids: uploaded(5).map(&:id)) }
        .to raise_error(Sharlayan::ChatService::Error, /up to 4 attachments/)
    end
  end

  describe 'receiving' do
    let(:bob) { Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/bob', inbox_url: 'https://remote.test/users/bob/inbox') }

    def note_with(count)
      {
        'type' => 'Create',
        'actor' => bob.uri,
        'object' => {
          'id' => 'https://remote.test/chat/messages/1',
          'type' => 'Note',
          'attributedTo' => bob.uri,
          '_misskey_talk' => true,
          '_misskey_content' => 'hello',
          'to' => [ActivityPub::TagManager.instance.uri_for(account)],
          'attachment' => Array.new(count) { |index| { 'type' => 'Document', 'mediaType' => 'image/png', 'url' => "https://remote.test/files/#{index}.png", 'name' => "picture #{index}" } },
        },
      }
    end

    before do
      user.settings[:chat_policy] = 'everyone'
      user.save!
    end

    [0, 1].each do |limit|
      it "keeps the whole message when the send limit is #{limit}" do
        Setting.chat_max_attachments = limit

        ActivityPub::Activity.factory(note_with(6), bob, delivered_to_account_id: account.id).perform

        message = ChatMessage.find_by!(uri: 'https://remote.test/chat/messages/1')
        expect(message.text).to eq('hello')
        expect(message.media_attachments.map(&:remote_url)).to eq(Array.new(6) { |index| "https://remote.test/files/#{index}.png" })
        expect(message.media_attachments.map(&:description)).to eq(Array.new(6) { |index| "picture #{index}" })
      ensure
        Setting.chat_max_attachments = 4
      end
    end

    it 'stops at the limit for remote posts' do
      ActivityPub::Activity.factory(note_with(Status.remote_media_attachments_limit + 2), bob, delivered_to_account_id: account.id).perform

      expect(ChatMessage.find_by!(uri: 'https://remote.test/chat/messages/1').media_attachments.size).to eq(Status.remote_media_attachments_limit)
    end
  end

  describe 'the Misskey API' do
    let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read write') }

    def mi_id(record)
      MisskeyCompat::MiId.encode(record.id)
    end

    def request_chat(endpoint, **params)
      post "/api/chat/#{endpoint}", params: params.merge(i: token.token), as: :json
    end

    before { Setting.misskey_compat_enabled = true }
    after { Setting.misskey_compat_enabled = false }

    it 'takes fileIds and describes every file, with the first one as fileId and file' do
      first, second = uploaded(2)

      request_chat('messages/create-to-user', toUserId: mi_id(other.account), fileIds: [mi_id(second), mi_id(first)])

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to include(
        fileId: mi_id(second),
        fileIds: [mi_id(second), mi_id(first)],
        file: include(id: mi_id(second)),
        files: [include(id: mi_id(second)), include(id: mi_id(first))]
      )
    end

    it 'still takes a single fileId, takes fileId and fileIds together without repeating a file, and answers with empty lists when there is no file' do
      media, first, second = uploaded(3)

      request_chat('messages/create-to-room', toRoomId: mi_id(conversation), fileId: mi_id(media))
      expect(response).to have_http_status(200)
      expect(response.parsed_body).to include(fileId: mi_id(media), fileIds: [mi_id(media)], files: [include(id: mi_id(media))])

      request_chat('messages/create-to-room', toRoomId: mi_id(conversation), fileId: mi_id(first), fileIds: [mi_id(first), mi_id(second)])
      expect(response).to have_http_status(200)
      expect(response.parsed_body[:fileIds]).to eq([mi_id(first), mi_id(second)])

      request_chat('messages/create-to-room', toRoomId: mi_id(conversation), text: 'hi')
      expect(response.parsed_body).to include(fileId: nil, file: nil, fileIds: [], files: [])
    end

    it 'refuses fileIds that are not a list of IDs' do
      request_chat('messages/create-to-room', toRoomId: mi_id(conversation), fileIds: 'nope')
      expect(response).to have_http_status(400)

      request_chat('messages/create-to-room', toRoomId: mi_id(conversation), fileIds: [{ id: 1 }])
      expect(response).to have_http_status(400)
    end
  end
end
