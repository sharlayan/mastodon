# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Incoming ActivityPub chat messages', type: :model do
  let(:local) { Fabricate(:user, account_attributes: { username: 'alice' }) }
  let(:alice) { local.account }
  let(:bob) { Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/bob', inbox_url: 'https://remote.test/users/bob/inbox') }

  let(:payload) do
    {
      'type' => 'Create',
      'actor' => bob.uri,
      'object' => {
        'id' => 'https://remote.test/chat/messages/1',
        'type' => 'Note',
        'attributedTo' => bob.uri,
        '_misskey_talk' => true,
        '_misskey_content' => 'hello',
        'content' => 'hello',
        'published' => '2026-11-02T00:00:00Z',
        'to' => [ActivityPub::TagManager.instance.uri_for(alice)],
      },
    }
  end

  before do
    Setting.chat_enabled = true
    Setting.chat_federation_enabled = true
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_federation_enabled = false
  end

  it 'creates a chat message instead of a status' do
    expect do
      ActivityPub::Activity.factory(payload, bob, delivered_to_account_id: alice.id).perform
    end.to change(ChatMessage, :count).by(1)
    expect(Status.count).to eq(0)
  end

  %w(Create Update).each do |type|
    it "handles a dereferenced chat #{type} without creating a status" do
      object = payload['object'].merge('@context' => 'https://www.w3.org/ns/activitystreams')
      stub_request(:get, object['id']).to_return(body: object.to_json, headers: { 'Content-Type' => 'application/activity+json' })

      ActivityPub::Activity.factory(payload.merge('type' => type, 'object' => object['id']), bob, delivered_to_account_id: alice.id).perform

      expect(ChatMessage.find_by(uri: object['id'])).to be_present
      expect(Status.where(uri: object['id'])).to be_empty
    end

    it "drops a dereferenced chat #{type} when federation is disabled" do
      Setting.chat_federation_enabled = false
      object = payload['object'].merge('@context' => 'https://www.w3.org/ns/activitystreams')
      stub_request(:get, object['id']).to_return(body: object.to_json, headers: { 'Content-Type' => 'application/activity+json' })

      ActivityPub::Activity.factory(payload.merge('type' => type, 'object' => object['id']), bob, delivered_to_account_id: alice.id).perform

      expect(ChatMessage.where(uri: object['id'])).to be_empty
      expect(Status.where(uri: object['id'])).to be_empty
    end
  end

  it 'does not allow a suspended actor to create a new message through Update' do
    bob.suspend!
    json = payload.merge('@context' => 'https://www.w3.org/ns/activitystreams', 'type' => 'Update')

    ActivityPub::ProcessActivityService.new.call(json.to_json, bob, delivered_to_account_id: alice.id)

    expect(ChatMessage.where(uri: payload['object']['id'])).to be_empty
    expect(Status.where(uri: payload['object']['id'])).to be_empty
  end

  it 'finds the local recipient from the numeric AP inbox URI' do
    payload['object']['to'] = [ActivityPub::TagManager.instance.uri_for_account_id(alice.id)]

    expect do
      ActivityPub::Activity.factory(payload, bob).perform
    end.to change(ChatMessage, :count).by(1)
  end

  it 'drops a policy-denied 1:1 message with 200' do
    alice.user.settings[:chat_policy] = 'none'
    alice.user.save!

    expect do
      ActivityPub::Activity.factory(payload, bob, delivered_to_account_id: alice.id).perform
    end.to_not change(ChatMessage, :count)
  end

  it 'does not resurrect a deleted message' do
    delete_payload = {
      'type' => 'Delete',
      'actor' => bob.uri,
      'object' => {
        'id' => payload['object']['id'],
        'type' => 'Tombstone',
        'formerType' => 'Note',
      },
    }

    ActivityPub::Activity.factory(delete_payload, bob).perform
    ActivityPub::Activity.factory(payload, bob, delivered_to_account_id: alice.id).perform

    expect(ChatMessage.find_by(uri: payload['object']['id'])).to be_nil
  end

  it 'rejects an invitation when group invites are disabled' do
    alice.user.settings[:chat_allow_group_invites] = false
    alice.user.save!

    invite = {
      'type' => 'Invite',
      'actor' => bob.uri,
      'target' => ActivityPub::TagManager.instance.uri_for(alice),
      'object' => {
        'id' => 'https://remote.test/chat/rooms/9',
        'type' => 'Group',
        'name' => 'Remote room',
        'attributedTo' => bob.uri,
      },
    }

    expect do
      ActivityPub::Activity.factory(invite, bob).perform
    end.to change(ActivityPub::DeliveryWorker.jobs, :size).by(1)
    expect(ChatConversation.find_by(uri: 'https://remote.test/chat/rooms/9')).to be_nil
  end
end
