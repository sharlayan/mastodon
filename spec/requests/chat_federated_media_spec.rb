# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Federated chat attachments' do
  let(:service) { Sharlayan::ChatService.new }
  let(:owner) { Fabricate(:user).account }
  let(:bob) { Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/bob', inbox_url: 'https://remote.test/users/bob/inbox') }
  let(:bea) { Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/bea', inbox_url: 'https://remote.test/users/bea/inbox') }
  let(:carol) { Fabricate(:account, domain: 'other.test', uri: 'https://other.test/users/carol', inbox_url: 'https://other.test/users/carol/inbox') }
  let(:room) do
    ChatConversation.create!(conversation_type: :group, owner_account: owner, title: 'Room').tap do |record|
      record.update!(uri: "https://cb6e6126.ngrok.io/chat/rooms/#{record.id}")
      record.memberships.create!(account: owner, role: :owner)
      record.memberships.create!(account: bob)
      record.memberships.create!(account: carol)
    end
  end
  let(:media) { Fabricate(:media_attachment, account: owner, status: nil) }
  let(:message) { service.create_message(owner, room, text: 'look', media_ids: [media.id]) }

  before do
    Setting.chat_enabled = true
    Setting.chat_federation_enabled = true
    room
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_federation_enabled = false
  end

  def delivered_url(inbox, type)
    job = ActivityPub::DeliveryWorker.jobs.find { |item| item['args'][2] == inbox && JSON.parse(item['args'][0])['type'] == type }
    JSON.parse(job['args'][0]).dig('object', 'attachment', 0, 'url')
  end

  def fetch(url)
    uri = URI.parse(url)
    get "#{uri.path}?#{uri.query}"
  end

  it 'gives each server its own address for an attachment' do
    message

    expect(delivered_url(bob.inbox_url, 'Create')).to include("/media_proxy/#{media.id}/original?token=")
    expect(delivered_url(carol.inbox_url, 'Create')).to include("/media_proxy/#{media.id}/original?token=")
    expect(delivered_url(bob.inbox_url, 'Create')).to_not eq(delivered_url(carol.inbox_url, 'Create'))
  end

  it 'does the same when the message is edited' do
    message
    service.update_message(owner, message, text: 'changed')

    expect(delivered_url(bob.inbox_url, 'Update')).to_not eq(delivered_url(carol.inbox_url, 'Update'))
  end

  it 'opens for a server that has a current member' do
    message

    fetch(delivered_url(bob.inbox_url, 'Create'))

    expect(response).to have_http_status(:redirect)
  end

  it 'closes for a server once its last member is removed' do
    message
    url = delivered_url(bob.inbox_url, 'Create')

    service.kick(owner, room, bob)
    fetch(url)

    expect(response).to have_http_status(404)
  end

  it 'stays open while the server has another member' do
    room.memberships.create!(account: bea)
    message
    url = delivered_url(bob.inbox_url, 'Create')

    service.kick(owner, room, bob)
    fetch(url)

    expect(response).to have_http_status(:redirect)
  end

  it 'stays open for other servers when one is removed' do
    message
    url = delivered_url(carol.inbox_url, 'Create')

    service.kick(owner, room, bob)
    fetch(url)

    expect(response).to have_http_status(:redirect)
  end

  it 'closes while the only member of a server is suspended' do
    message
    url = delivered_url(bob.inbox_url, 'Create')

    bob.suspend!
    fetch(url)

    expect(response).to have_http_status(404)
  end

  it 'does not take a token that names no server' do
    token = Rails.application.message_verifier('sharlayan_chat_media').generate({ 'id' => message.media_attachments.first.id }, expires_in: 1.year, purpose: :chat_media)

    get "/media_proxy/#{media.id}/original", params: { token: token }

    expect(response).to have_http_status(404)
  end

  it 'does not take a token issued for another attachment' do
    other_media = Fabricate(:media_attachment, account: owner, status: nil)
    service.create_message(owner, room, text: 'other', media_ids: [other_media.id])
    token = Sharlayan::ChatFederation::MediaToken.generate(other_media, domain: bob.domain)
    message

    get "/media_proxy/#{media.id}/original", params: { token: token }

    expect(response).to have_http_status(404)
  end

  it 'gives a server that fetches the Note its own address' do
    message

    get "/chat/messages/#{message.id}", headers: { 'Accept' => 'application/activity+json' }, sign_with: bob
    url = response.parsed_body.dig('attachment', 0, 'url')
    service.kick(owner, room, carol)
    fetch(url)
    expect(response).to have_http_status(:redirect)

    service.kick(owner, room, bob)
    fetch(url)
    expect(response).to have_http_status(404)
  end

  it 'keeps one payload for a message without attachments' do
    service.create_message(owner, room, text: 'plain')

    jobs = ActivityPub::DeliveryWorker.jobs.select { |item| JSON.parse(item['args'][0])['type'] == 'Create' }
    expect(jobs.map { |item| item['args'][0] }.uniq.size).to eq(1)
  end

  describe 'delivery to a shared inbox' do
    let(:shared) { 'https://remote.test/inbox' }

    before do
      bob.update!(shared_inbox_url: shared)
      room.memberships.create!(account: bea)
      bea.update!(shared_inbox_url: shared)
      ActivityPub::DeliveryWorker.jobs.clear
    end

    it 'sends a message once to a server with a shared inbox' do
      service.create_message(owner, room, text: 'hello')

      inboxes = ActivityPub::DeliveryWorker.jobs.map { |item| item['args'][2] }
      expect(inboxes).to contain_exactly(shared, carol.inbox_url)
    end

    it 'sends a removal once to that server' do
      service.kick(owner, room, carol)
      ActivityPub::DeliveryWorker.jobs.clear

      service.kick(owner, room, bob)

      expect(ActivityPub::DeliveryWorker.jobs.map { |item| item['args'][2] }).to eq([shared])
    end

    it 'names the local recipient so that a direct message arrives through a shared inbox' do
      alice = Fabricate(:user).account
      alice.user.settings[:chat_policy] = 'everyone'
      alice.user.save!
      note = {
        'type' => 'Create',
        'actor' => bob.uri,
        'object' => {
          'id' => 'https://remote.test/chat/messages/9',
          'type' => 'Note',
          'attributedTo' => bob.uri,
          '_misskey_talk' => true,
          '_misskey_content' => 'hi',
          'to' => [ActivityPub::TagManager.instance.uri_for(alice)],
        },
      }

      ActivityPub::Activity.factory(note, bob).perform

      expect(ChatMessage.find_by(uri: 'https://remote.test/chat/messages/9').chat_conversation.accounts).to include(alice)
    end
  end
end
