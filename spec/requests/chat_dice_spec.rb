# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Chat dice rolls' do
  include_context 'with an open chat policy'

  include_context 'with API authentication', oauth_scopes: 'read write'

  let(:service) { Sharlayan::ChatService.new }
  let(:account) { user.account }
  let(:bob) { Fabricate(:account, domain: 'remote.test', uri: 'https://remote.test/users/bob', inbox_url: 'https://remote.test/users/bob/inbox') }
  let(:room) { service.create_conversation(account, type: :group, title: 'Room') }
  let(:dice) { { 'version' => 1, 'engine' => '@dice-roller/rpg-dice-roller', 'engineVersion' => '5.5.1', 'notation' => '1d20', 'total' => 17, 'output' => '1d20: [17] = 17' } }

  before do
    Setting.chat_enabled = true
    Setting.chat_federation_enabled = true
  end

  after do
    Setting.chat_enabled = false
    Setting.chat_federation_enabled = false
  end

  def post_message(text)
    post "/api/v1/chat/conversations/#{room.id}/messages", params: { text: text }, headers: headers, as: :json
  end

  it 'rolls /dice with the Node engine once, keeps the result and makes the message immutable' do
    post_message('/dice 2d6+1')

    expect(response).to have_http_status(200)
    body = response.parsed_body
    expect(body).to include('content' => '/dice 2d6+1', 'editable' => false)
    expect(body['dice']).to include('version' => 1, 'engine' => '@dice-roller/rpg-dice-roller', 'engineVersion' => '5.5.1', 'notation' => '2d6+1', 'total' => be_between(3, 13))
    expect(body['dice']['output']).to start_with('2d6+1: [')

    message = ChatMessage.find(body['id'])
    expect(message.dice).to eq(body['dice'])
    expect(Sharlayan::ChatFederation::Payload.create(message)['object']['_misskey_dice']).to eq(body['dice'])

    patch "/api/v1/chat/messages/#{message.id}", params: { text: '/dice 1d20' }, headers: headers, as: :json
    expect(response).to have_http_status(422)
    expect(message.reload).to have_attributes(text: '/dice 2d6+1', dice: body['dice'])

    post_message('/dice')
    expect(response.parsed_body['dice']).to include('notation' => '1d6')

    service.delete_message(account, message)
    expect(message.reload.dice).to be_nil
  end

  it 'reports unreadable, oversized and busy rolls without creating a message' do
    expect do
      post_message('/dice nope(')
      expect(response).to have_http_status(422)
      expect(response.parsed_body).to include('error_code' => 'DICE_INVALID')

      post_message("/dice #{'(' * 40}1#{')' * 40}")
      expect(response.parsed_body).to include('error_code' => 'DICE_LIMIT')

      redis.set("chat_dice_user:#{account.id}", 'other', px: 10_000)
      post_message('/dice 1d6')
      expect(response).to have_http_status(429)
      expect(response.parsed_body).to include('error_code' => 'DICE_BUSY')
    end.to_not change(ChatMessage, :count)
  ensure
    redis.del("chat_dice_user:#{account.id}")
  end

  it 'leaves ordinary and compatibility API messages as plain text' do
    post_message('/dicey 1d6')
    expect(response.parsed_body).to include('content' => '/dicey 1d6', 'dice' => nil, 'editable' => true)

    message = service.create_message(account, room, text: '/dice 1d6')
    expect(message.dice).to be_nil
  end

  describe 'federation' do
    let(:payload) do
      {
        'type' => 'Create',
        'actor' => bob.uri,
        'object' => {
          'id' => 'https://remote.test/chat/messages/1',
          'type' => 'Note',
          'attributedTo' => bob.uri,
          '_misskey_talk' => true,
          '_misskey_content' => '/dice 1d20',
          'content' => '/dice 1d20',
          '_misskey_dice' => dice,
          'published' => '2026-11-12T00:00:00Z',
          'to' => [ActivityPub::TagManager.instance.uri_for(account)],
        },
      }
    end

    it 'stores a valid remote result, drops a malformed one and ignores edits of dice messages' do
      ActivityPub::Activity.factory(payload, bob, delivered_to_account_id: account.id).perform
      message = ChatMessage.find_by!(uri: 'https://remote.test/chat/messages/1')
      expect(message.dice).to eq(dice)

      update = payload.merge('type' => 'Update', 'object' => payload['object'].merge('_misskey_content' => '/dice 1d4', 'updated' => '2026-11-12T00:01:00Z'))
      ActivityPub::Activity.factory(update, bob, delivered_to_account_id: account.id).perform
      expect(message.reload).to have_attributes(text: '/dice 1d20', dice: dice, edited_at: nil)

      tampered = payload.deep_merge('object' => { 'id' => 'https://remote.test/chat/messages/2', '_misskey_dice' => dice.merge('extra' => true) })
      ActivityPub::Activity.factory(tampered, bob, delivered_to_account_id: account.id).perform
      expect(ChatMessage.find_by!(uri: 'https://remote.test/chat/messages/2').dice).to be_nil
    end
  end

  describe Sharlayan::ChatDice do
    it 'reads only a leading /dice command and defaults to 1d6' do
      expect(described_class.notation('/dice')).to eq('1d6')
      expect(described_class.notation("  /dice\u3000d20 ")).to eq('d20')
      expect(described_class.notation('/dicey')).to be_nil
      expect(described_class.notation('roll /dice 1d6')).to be_nil
    end

    it 'accepts only stored results shaped like CherryPick results' do
      expect(described_class.parse(dice)).to eq(dice)
      expect(described_class.parse(dice.merge('total' => 2.5))).to include('total' => 2.5)
      expect(described_class.parse(dice.merge('engine' => 'other'))).to be_nil
      expect(described_class.parse(dice.merge('total' => '17'))).to be_nil
      expect(described_class.parse(dice.merge('output' => "a\0b"))).to be_nil
      expect(described_class.parse(dice.merge('engineVersion' => 'latest'))).to be_nil
      expect(described_class.parse(dice.merge('notation' => 'd' * 513))).to be_nil
      expect(described_class.parse(dice.except('output'))).to be_nil
    end
  end
end
