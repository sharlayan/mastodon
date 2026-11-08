# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Chat federation in roleplay mode' do
  include_context 'with an open chat policy'

  include_context 'with API authentication', oauth_scopes: 'read write'

  let(:service) { Sharlayan::ChatService.new }
  let(:remote) { Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/bob', inbox_url: 'https://remote.test/users/bob/inbox', can_chat: true, chat_scope: 'everyone') }
  let(:room) { service.create_conversation(user.account, type: :group, title: 'Room') }

  around { |example| ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') { example.run } }

  before do
    Setting.chat_enabled = true
    Setting.chat_federation_enabled = true
    ActivityPub::DeliveryWorker.jobs.clear
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_federation_enabled = true
  end

  it 'does not take chat activities from other servers even when the stored setting is on' do
    expect(Sharlayan::ChatFederation::Incoming.enabled?).to be(false)
  end

  it 'does not advertise chat to other servers' do
    json = serialized_record_json(user.account, ActivityPub::ActorSerializer, adapter: ActivityPub::Adapter)

    expect(json['_misskey_canChat']).to be(false)
  end

  it 'does not open a direct conversation with a remote account' do
    expect { service.create_conversation(user.account, type: :direct, account_ids: [remote.id]) }
      .to raise_error(Sharlayan::ChatService::Error, 'Chat federation is disabled')
  end

  it 'does not invite a remote account' do
    expect { service.invite(user.account, room, remote) }.to raise_error(Sharlayan::ChatService::Error, 'Chat federation is disabled')
  end

  it 'does not send anything for a room that already has a remote member' do
    room.memberships.create!(account: remote)

    expect { service.create_message(user.account, room, text: 'hello') }.to raise_error(Sharlayan::ChatService::Error, 'Chat federation is disabled')
    service.archive(user.account, room, archived: true)

    expect(ActivityPub::DeliveryWorker.jobs).to be_empty
  end

  it 'does not fetch attachments of remote chat messages' do
    room.memberships.create!(account: remote)
    message = room.messages.create!(account: remote, text: 'remote', uri: 'https://remote.test/notes/1')
    media = Fabricate(:media_attachment, account: remote, remote_url: 'https://remote.test/files/1.png', file: nil)
    message.chat_message_media_attachments.create!(media_attachment: media)
    request = stub_request(:get, 'https://remote.test/files/1.png')

    ChatMediaDownloadWorker.new.perform(message.id)

    expect(request).to_not have_been_requested
  end

  it 'does not fetch a remote chat attachment through the media proxy' do
    room.memberships.create!(account: remote)
    message = room.messages.create!(account: remote, text: 'remote', uri: 'https://remote.test/notes/1')
    media = Fabricate(:media_attachment, account: remote, remote_url: 'https://remote.test/files/2.png', file: nil)
    message.chat_message_media_attachments.create!(media_attachment: media)
    request = stub_request(:get, 'https://remote.test/files/2.png')
    sign_in user

    get "/media_proxy/#{media.id}/original"

    expect(request).to_not have_been_requested
  end

  it 'tells clients that chat federation is off' do
    get '/api/v1/chat/settings', headers: headers

    expect(response.parsed_body[:federation_enabled]).to be(false)
  end

  it 'reports remote accounts as unable to chat through the Misskey-compatible API' do
    expect(MisskeyCompat::UserSerializer.serialize(remote, detailed: true)).to include(canChat: false)
  end
end
