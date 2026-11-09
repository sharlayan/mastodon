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

  it 'does not take chat activities from other servers even when the stored setting is on, and tells servers and clients that chat federation is off' do
    expect(Sharlayan::ChatFederation::Incoming.enabled?).to be(false)
    expect(serialized_record_json(user.account, ActivityPub::ActorSerializer, adapter: ActivityPub::Adapter)['_misskey_canChat']).to be(false)
    expect(MisskeyCompat::UserSerializer.serialize(remote, detailed: true)).to include(canChat: false)

    get '/api/v1/chat/settings', headers: headers

    expect(response.parsed_body[:federation_enabled]).to be(false)
  end

  it 'does not open a direct conversation with or invite a remote account' do
    expect { service.create_conversation(user.account, type: :direct, account_ids: [remote.id]) }
      .to raise_error(Sharlayan::ChatService::Error, 'Chat federation is disabled')
    expect { service.invite(user.account, room, remote) }.to raise_error(Sharlayan::ChatService::Error, 'Chat federation is disabled')
  end

  it 'does not send anything for a room that already has a remote member' do
    room.memberships.create!(account: remote)

    expect { service.create_message(user.account, room, text: 'hello') }.to raise_error(Sharlayan::ChatService::Error, 'Chat federation is disabled')
    service.archive(user.account, room, archived: true)

    expect(ActivityPub::DeliveryWorker.jobs).to be_empty
  end

  it 'does not fetch attachments of remote chat messages, neither in the worker nor through the media proxy' do
    room.memberships.create!(account: remote)
    message = room.messages.create!(account: remote, text: 'remote', uri: 'https://remote.test/notes/1')
    media = %w(1 2).map { |name| Fabricate(:media_attachment, account: remote, remote_url: "https://remote.test/files/#{name}.png", file: nil) }
    media.each { |attachment| message.chat_message_media_attachments.create!(media_attachment: attachment) }
    requests = %w(1 2).map { |name| stub_request(:get, "https://remote.test/files/#{name}.png") }
    sign_in user

    ChatMediaDownloadWorker.new.perform(message.id)
    get "/media_proxy/#{media.last.id}/original"

    requests.each { |request| expect(request).to_not have_been_requested }
  end
end
